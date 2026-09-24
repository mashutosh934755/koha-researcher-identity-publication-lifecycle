#!/usr/bin/perl

use strict;
use warnings;

use C4::Context;
use Fcntl qw(:flock);
use POSIX qw(strftime);

my $lock_file = '/var/lock/koha-researcher-expiry-lifecycle.lock';

open my $lock_fh, '>', $lock_file
    or die "Cannot open lock file $lock_file: $!\n";

unless ( flock($lock_fh, LOCK_EX | LOCK_NB) ) {
    print "Another lifecycle run is already active. Exiting safely.\n";
    exit 0;
}

my $dbh = C4::Context->dbh;
$dbh->{RaiseError} = 1;
$dbh->{PrintError} = 0;

my $run_time = strftime('%Y-%m-%d %H:%M:%S', localtime);

print "============================================================\n";
print " RESEARCHER EXPIRY LIFECYCLE\n";
print " Run time: $run_time\n";
print "============================================================\n";

my $candidates = $dbh->selectall_arrayref(
    q{
        SELECT
            b.borrowernumber,
            b.cardnumber,
            b.firstname,
            b.surname,
            b.dateexpiry,
            c.profile_status,
            c.verification_status,
            c.employment_status,
            c.public_visibility,
            c.sync_enabled,
            c.relieving_date,
            c.status_reason
        FROM borrowers b
        JOIN custom_profile_details c
          ON c.borrowernumber = b.borrowernumber
        WHERE b.dateexpiry IS NOT NULL
          AND b.dateexpiry < CURDATE()
          AND c.employment_status = 'active'
        ORDER BY b.borrowernumber
    },
    { Slice => {} }
);

if ( !@{$candidates} ) {
    print "No expired active researcher profiles found.\n";
    print "LIFECYCLE_NO_CHANGES\n";
    exit 0;
}

my $processed = 0;
my $failed    = 0;

for my $row ( @{$candidates} ) {

    my $borrowernumber = $row->{borrowernumber};
    my $name = join ' ',
        grep { defined($_) && $_ ne '' }
        ( $row->{firstname}, $row->{surname} );

    my $expiry = $row->{dateexpiry};

    eval {
        $dbh->begin_work;

        # Lock the researcher profile to avoid duplicate concurrent changes.
        my $current = $dbh->selectrow_hashref(
            q{
                SELECT
                    profile_status,
                    verification_status,
                    employment_status,
                    public_visibility,
                    sync_enabled,
                    relieving_date,
                    status_reason
                FROM custom_profile_details
                WHERE borrowernumber = ?
                FOR UPDATE
            },
            undef,
            $borrowernumber
        );

        die "Researcher profile disappeared during processing"
            unless $current;

        if ( ($current->{employment_status} // '') ne 'active' ) {
            $dbh->rollback;
            print "SKIP borrower=$borrowernumber already non-active\n";
            return;
        }

        my $old_value = join '; ',
            'profile_status='
                . ($current->{profile_status} // ''),
            'verification_status='
                . ($current->{verification_status} // ''),
            'employment_status='
                . ($current->{employment_status} // ''),
            'public_visibility='
                . ($current->{public_visibility} // 0),
            'sync_enabled='
                . ($current->{sync_enabled} // 0),
            'relieving_date='
                . ($current->{relieving_date} // '');

        my $reason =
            "Automatically marked former because patron card expired on $expiry";

        # Verified former profiles remain publicly visible.
        # Pending/rejected profiles remain hidden.
        $dbh->do(
            q{
                UPDATE custom_profile_details
                SET
                    employment_status = 'former',
                    relieving_date = COALESCE(
                        relieving_date,
                        ?
                    ),
                    sync_enabled = 0,
                    public_visibility =
                        CASE
                            WHEN verification_status = 'verified'
                            THEN 1
                            ELSE 0
                        END,
                    status_reason = ?,
                    updated_at = NOW()
                WHERE borrowernumber = ?
                  AND employment_status = 'active'
            },
            undef,
            $expiry,
            $reason,
            $borrowernumber
        );

        $dbh->do(
            q{
                UPDATE researcher_affiliations
                SET
                    is_current = 0,
                    end_date = COALESCE(end_date, ?),
                    updated_at = NOW()
                WHERE borrowernumber = ?
                  AND is_current = 1
            },
            undef,
            $expiry,
            $borrowernumber
        );

        my $new_visibility =
            ($current->{verification_status} // '') eq 'verified'
            ? 1
            : 0;

        my $new_value = join '; ',
            'employment_status=former',
            'sync_enabled=0',
            'public_visibility=' . $new_visibility,
            'relieving_date=' . $expiry;

        $dbh->do(
            q{
                INSERT INTO researcher_audit_log
                (
                    borrowernumber,
                    action_type,
                    old_value,
                    new_value,
                    action_reason,
                    performed_by,
                    source,
                    ip_address,
                    created_at
                )
                VALUES (?, ?, ?, ?, ?, NULL, 'system', NULL, NOW())
            },
            undef,
            $borrowernumber,
            'researcher_marked_former',
            $old_value,
            $new_value,
            $reason
        );

        $dbh->commit;
        $processed++;

        print
            "FORMER borrower=$borrowernumber"
            . " card=" . ($row->{cardnumber} // '')
            . " name=$name"
            . " expiry=$expiry"
            . " sync=disabled"
            . " public=" . ($new_visibility ? 'visible' : 'hidden')
            . "\n";
    };

    if ($@) {
        my $error = $@;
        eval { $dbh->rollback };
        $failed++;

        $error =~ s/\s+$//;

        print STDERR
            "ERROR borrower=$borrowernumber: $error\n";
    }
}

print "------------------------------------------------------------\n";
print "Processed: $processed\n";
print "Failed:    $failed\n";

if ($failed) {
    die "LIFECYCLE_COMPLETED_WITH_ERRORS\n";
}

print "RESEARCHER_EXPIRY_LIFECYCLE_OK\n";
