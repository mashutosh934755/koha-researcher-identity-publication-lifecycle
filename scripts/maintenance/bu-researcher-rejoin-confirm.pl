#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use C4::Context;

my $candidate_id;
my $apply       = 0;
my $reviewed_by;
my $help        = 0;

GetOptions(
    'candidate=i'   => \$candidate_id,
    'apply!'        => \$apply,
    'reviewed-by=i' => \$reviewed_by,
    'help!'         => \$help,
) or die "Invalid options\n";


sub usage {

    print <<'TXT';

BU Researcher Rejoin Confirmation Engine V2

DRY RUN:
  bu-researcher-rejoin-confirm.pl --candidate 12

APPLY:
  bu-researcher-rejoin-confirm.pl \
      --candidate 12 \
      --apply \
      --reviewed-by 51

APPLY performs a controlled rejoin:

  old permanent UUID retained
  old patron history retained
  old publication links retained
  canonical profile re-anchored to new borrower
  new patron link created
  new employment episode opened
  researcher marked current
  candidate marked confirmed
  audit event recorded

TXT
}


if ($help || !$candidate_id) {
    usage();
    exit($help ? 0 : 1);
}


if ($apply && !$reviewed_by) {
    die
        "--apply requires --reviewed-by <staff borrowernumber>\n";
}


my $dbh = C4::Context->dbh;


# ------------------------------------------------------------
# Candidate
# ------------------------------------------------------------

my $candidate =
    $dbh->selectrow_hashref(
        q{
            SELECT
                rc.id,
                rc.new_borrowernumber,
                rc.candidate_researcher_uuid,
                rc.confidence_score,
                rc.review_status,

                rc.orcid_match,
                rc.scopus_match,
                rc.wos_match,
                rc.email_match,
                rc.name_match,

                p.canonical_name,
                p.lifecycle_status,
                p.verification_status

            FROM researcher_rejoin_candidates rc

            JOIN researcher_persons p
              ON p.researcher_uuid =
                 rc.candidate_researcher_uuid

            WHERE rc.id = ?
        },
        undef,
        $candidate_id
    );


die "Candidate $candidate_id not found\n"
    unless $candidate;


my $uuid =
    $candidate->{candidate_researcher_uuid};

my $new_bn =
    $candidate->{new_borrowernumber};


print "============================================================\n";
print " RESEARCHER REJOIN CONFIRMATION V2\n";
print "============================================================\n";

print "Candidate ID : $candidate_id\n";
print "Researcher   : "
    . ($candidate->{canonical_name} // '')
    . "\n";

print "UUID         : $uuid\n";
print "New borrower : $new_bn\n";
print "Score        : "
    . ($candidate->{confidence_score} // '')
    . "\n";

print "Review state : "
    . ($candidate->{review_status} // '')
    . "\n";


# ------------------------------------------------------------
# Validation
# ------------------------------------------------------------

my @errors;


if (($candidate->{review_status} // '') ne 'pending') {
    push @errors,
        "Candidate is not pending";
}


if (($candidate->{lifecycle_status} // '') ne 'former') {
    push @errors,
        "Permanent researcher is not currently former";
}


my $new_borrower =
    $dbh->selectrow_hashref(
        q{
            SELECT
                borrowernumber,
                cardnumber,
                firstname,
                surname,
                email,
                dateenrolled,
                dateexpiry,
                categorycode,
                branchcode

            FROM borrowers
            WHERE borrowernumber = ?
        },
        undef,
        $new_bn
    );


if (!$new_borrower) {
    push @errors,
        "New Koha borrower does not exist";
}


my $already_linked =
    $dbh->selectrow_hashref(
        q{
            SELECT
                researcher_uuid,
                link_status
            FROM researcher_patron_links
            WHERE borrowernumber = ?
        },
        undef,
        $new_bn
    );


if ($already_linked) {

    push @errors,
        "New borrower already linked to permanent UUID "
        . $already_linked->{researcher_uuid};
}


my $current_count =
    $dbh->selectrow_array(
        q{
            SELECT COUNT(*)
            FROM researcher_patron_links
            WHERE researcher_uuid = ?
              AND link_status = 'current'
        },
        undef,
        $uuid
    ) || 0;


if ($current_count) {

    push @errors,
        "Researcher already has a current patron account";
}


my $profiles =
    $dbh->selectall_arrayref(
        q{
            SELECT *
            FROM custom_profile_details
            WHERE researcher_uuid = ?
        },
        { Slice => {} },
        $uuid
    );


if (@{$profiles} != 1) {

    push @errors,
        "Expected exactly one canonical profile; found "
        . scalar(@{$profiles});
}


my $new_profile_collision =
    $dbh->selectrow_array(
        q{
            SELECT COUNT(*)
            FROM custom_profile_details
            WHERE borrowernumber = ?
        },
        undef,
        $new_bn
    ) || 0;


if ($new_profile_collision) {

    push @errors,
        "New borrower already owns custom_profile_details";
}


my $reviewer_exists = 0;

if ($apply) {

    $reviewer_exists =
        $dbh->selectrow_array(
            q{
                SELECT COUNT(*)
                FROM borrowers
                WHERE borrowernumber = ?
            },
            undef,
            $reviewed_by
        ) || 0;

    if (!$reviewer_exists) {

        push @errors,
            "Reviewer borrower $reviewed_by does not exist";
    }
}


my $old_profile =
    @{$profiles} == 1
    ? $profiles->[0]
    : {};


my $old_bn =
    $old_profile->{borrowernumber};


print "\n===== CANONICAL PROFILE =====\n";

print "Old profile borrower : "
    . ($old_bn // '')
    . "\n";

print "Profile employment   : "
    . ($old_profile->{employment_status} // '')
    . "\n";

print "ORCID                : "
    . ($old_profile->{orcid} // '')
    . "\n";

print "Scopus ID            : "
    . ($old_profile->{scopus_author_id} // '')
    . "\n";

print "WoS ID               : "
    . ($old_profile->{researcher_id} // '')
    . "\n";


# ------------------------------------------------------------
# Historical dependency inventory
# ------------------------------------------------------------

my $publication_links =
    defined($old_bn)
    ? (
        $dbh->selectrow_array(
            q{
                SELECT COUNT(*)
                FROM researcher_publication_links
                WHERE borrowernumber = ?
            },
            undef,
            $old_bn
        ) || 0
    )
    : 0;


print "\n===== HISTORY PRESERVATION =====\n";

print "Historical publication links on old borrower: "
    . $publication_links
    . "\n";

print "These publication links will NOT be moved.\n";


print "\n===== NEW KOHA ACCOUNT =====\n";

if ($new_borrower) {

    print "Borrowernumber : "
        . $new_borrower->{borrowernumber}
        . "\n";

    print "Cardnumber     : "
        . ($new_borrower->{cardnumber} // '')
        . "\n";

    print "Name           : "
        . join(
            ' ',
            grep {
                defined($_)
                && $_ ne ''
            }
            (
                $new_borrower->{firstname},
                $new_borrower->{surname}
            )
        )
        . "\n";

    print "Email          : "
        . ($new_borrower->{email} // '')
        . "\n";

    print "Date enrolled  : "
        . ($new_borrower->{dateenrolled} // '')
        . "\n";
}


print "\n===== PROPOSED ACTION =====\n";

print "1. Preserve UUID $uuid\n";
print "2. Preserve old patron link borrower $old_bn as former\n";
print "3. Preserve all historical publication links\n";
print "4. Move canonical profile anchor $old_bn -> $new_bn\n";
print "5. Reactivate canonical profile\n";
print "6. Create current patron link for $new_bn\n";
print "7. Open new employment episode\n";
print "8. Mark researcher current\n";
print "9. Confirm candidate\n";
print "10. Record rejoin audit event\n";


if (@errors) {

    print "\nSTATUS: BLOCKED\n";

    for my $e (@errors) {
        print " - $e\n";
    }

    exit 2;
}


if (!$apply) {

    print "\nSTATUS: READY_TO_APPLY\n";
    print "No database changes made.\n";
    print "REJOIN_CONFIRMATION_DRY_RUN_OK\n";

    exit 0;
}


# ------------------------------------------------------------
# APPLY TRANSACTION
# ------------------------------------------------------------

print "\n===== APPLYING CONFIRMED REJOIN =====\n";


eval {

    $dbh->begin_work;


    # Lock researcher.
    my $locked_person =
        $dbh->selectrow_hashref(
            q{
                SELECT *
                FROM researcher_persons
                WHERE researcher_uuid = ?
                FOR UPDATE
            },
            undef,
            $uuid
        );

    die "Researcher disappeared during transaction"
        unless $locked_person;


    # Lock candidate.
    my $locked_candidate =
        $dbh->selectrow_hashref(
            q{
                SELECT *
                FROM researcher_rejoin_candidates
                WHERE id = ?
                FOR UPDATE
            },
            undef,
            $candidate_id
        );

    die "Candidate disappeared during transaction"
        unless $locked_candidate;

    die "Candidate no longer pending"
        unless
            ($locked_candidate->{review_status} // '')
            eq 'pending';


    # Lock canonical profile.
    my $locked_profile =
        $dbh->selectrow_hashref(
            q{
                SELECT *
                FROM custom_profile_details
                WHERE researcher_uuid = ?
                FOR UPDATE
            },
            undef,
            $uuid
        );

    die "Canonical profile disappeared"
        unless $locked_profile;


    my $transaction_old_bn =
        $locked_profile->{borrowernumber};


    # --------------------------------------------------------
    # Ensure historical patron links are former.
    # --------------------------------------------------------

    $dbh->do(
        q{
            UPDATE researcher_patron_links

            SET
                link_status = 'former',
                valid_to =
                    COALESCE(
                        valid_to,
                        CURRENT_DATE
                    ),
                updated_at = NOW()

            WHERE researcher_uuid = ?
              AND link_status = 'current'
        },
        undef,
        $uuid
    );


    # --------------------------------------------------------
    # Re-anchor canonical operational profile.
    #
    # Old scholarly data remains linked to historical borrower
    # IDs. Only the active profile account changes.
    # --------------------------------------------------------

    $dbh->do(
        q{
            UPDATE custom_profile_details

            SET
                borrowernumber = ?,

                employment_status = 'active',
                relieving_date = NULL,

                sync_enabled = 1,

                public_visibility =
                    CASE
                        WHEN verification_status='verified'
                        THEN 1
                        ELSE public_visibility
                    END,

                status_reason =
                    'Researcher rejoined institution; canonical profile reactivated',

                email =
                    COALESCE(
                        NULLIF(?, ''),
                        email
                    ),

                first_name =
                    COALESCE(
                        NULLIF(?, ''),
                        first_name
                    ),

                last_name =
                    COALESCE(
                        NULLIF(?, ''),
                        last_name
                    ),

                joining_date =
                    COALESCE(
                        ?,
                        CURRENT_DATE
                    ),

                employee_id = NULL,

                updated_at = NOW()

            WHERE researcher_uuid = ?
        },
        undef,

        $new_bn,

        ($new_borrower->{email} // ''),
        ($new_borrower->{firstname} // ''),
        ($new_borrower->{surname} // ''),
        $new_borrower->{dateenrolled},

        $uuid
    );


    # --------------------------------------------------------
    # Create new current patron link.
    # --------------------------------------------------------

    $dbh->do(
        q{
            INSERT INTO researcher_patron_links
            (
                researcher_uuid,
                borrowernumber,
                cardnumber,
                employee_id,
                institutional_email,

                link_status,
                valid_from,
                valid_to,

                link_method,
                confidence_score,

                created_at,
                updated_at
            )
            VALUES
            (
                ?, ?, ?, NULL, ?,
                'current', ?, NULL,
                'confirmed_rejoin_v2', ?,
                NOW(), NOW()
            )
        },
        undef,

        $uuid,
        $new_bn,
        $new_borrower->{cardnumber},
        $new_borrower->{email},
        $new_borrower->{dateenrolled},
        $candidate->{confidence_score}
    );


    # --------------------------------------------------------
    # Close any accidentally-open employment episodes.
    # --------------------------------------------------------

    $dbh->do(
        q{
            UPDATE researcher_employment_episodes

            SET
                episode_status='completed',
                end_date=
                    COALESCE(
                        end_date,
                        CURRENT_DATE
                    ),
                updated_at=NOW()

            WHERE researcher_uuid=?
              AND episode_status='current'
        },
        undef,
        $uuid
    );


    # --------------------------------------------------------
    # Open new employment episode.
    # --------------------------------------------------------

    $dbh->do(
        q{
            INSERT INTO researcher_employment_episodes
            (
                researcher_uuid,
                borrowernumber,

                organisation_name,
                employee_id,
                department,
                designation,

                start_date,
                end_date,
                episode_status,
                source,

                created_at,
                updated_at
            )

            SELECT
                ?,
                ?,

                'Example University',
                NULL,
                department,
                designation,

                COALESCE(
                    ?,
                    CURRENT_DATE
                ),

                NULL,
                'current',
                'confirmed-rejoin-v2',

                NOW(),
                NOW()

            FROM custom_profile_details
            WHERE researcher_uuid=?
        },
        undef,

        $uuid,
        $new_bn,
        $new_borrower->{dateenrolled},
        $uuid
    );


    # --------------------------------------------------------
    # Permanent person becomes current.
    # --------------------------------------------------------

    $dbh->do(
        q{
            UPDATE researcher_persons

            SET
                lifecycle_status='current',
                updated_at=NOW()

            WHERE researcher_uuid=?
        },
        undef,
        $uuid
    );


    # --------------------------------------------------------
    # Candidate confirmation.
    # --------------------------------------------------------

    $dbh->do(
        q{
            UPDATE researcher_rejoin_candidates

            SET
                review_status='confirmed',
                reviewed_by=?,
                reviewed_at=NOW()

            WHERE id=?
              AND review_status='pending'
        },
        undef,
        $reviewed_by,
        $candidate_id
    );


    # --------------------------------------------------------
    # Onboarding status.
    # --------------------------------------------------------

    $dbh->do(
        q{
            UPDATE researcher_onboarding_log

            SET
                status='rejoin_confirmed',
                completed_at=NOW(),
                last_error=NULL

            WHERE borrowernumber=?
        },
        undef,
        $new_bn
    );


    # --------------------------------------------------------
    # Audit event.
    # --------------------------------------------------------

    $dbh->do(
        q{
            INSERT INTO researcher_identity_events
            (
                researcher_uuid,
                borrowernumber,
                event_type,
                old_value,
                new_value,
                event_reason,
                performed_by,
                created_at
            )
            VALUES
            (
                ?,
                ?,
                'researcher_rejoined',
                ?,
                ?,
                ?,
                ?,
                NOW()
            )
        },
        undef,

        $uuid,
        $new_bn,

        "canonical_profile_borrower=$transaction_old_bn",

        "canonical_profile_borrower=$new_bn",

        "Returning researcher confirmed; same permanent UUID retained",

        $reviewed_by
    );


    $dbh->commit;
};


if ($@) {

    my $error = $@;

    eval {
        $dbh->rollback;
    };

    die
        "REJOIN APPLY FAILED - transaction rolled back: "
        . $error;
}


print "\n============================================================\n";
print " REJOIN CONFIRMED SUCCESSFULLY\n";
print "============================================================\n";

print "Permanent UUID : $uuid\n";
print "Old borrower   : $old_bn\n";
print "New borrower   : $new_bn\n";
print "Reviewer       : $reviewed_by\n";

print "\nHistorical publications were NOT moved.\n";
print "REJOIN_CONFIRMATION_APPLY_OK\n";

exit 0;
