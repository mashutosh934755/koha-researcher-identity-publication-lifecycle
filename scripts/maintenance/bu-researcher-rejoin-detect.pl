#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use JSON::PP qw(encode_json);
use Digest::SHA qw(sha256_hex);

use C4::Context;

my $borrowernumber;
my $test_name;
my $test_email;
my $test_employee_id;
my $test_orcid;
my $test_scopus;
my $test_wos;

my $apply    = 0;
my $selftest = 0;
my $help     = 0;

GetOptions(
    'borrower=i'     => \$borrowernumber,

    'test-name=s'    => \$test_name,
    'test-email=s'   => \$test_email,
    'test-employee=s'=> \$test_employee_id,
    'test-orcid=s'   => \$test_orcid,
    'test-scopus=s'  => \$test_scopus,
    'test-wos=s'     => \$test_wos,

    'apply!'         => \$apply,
    'self-test!'     => \$selftest,
    'help!'          => \$help,
) or die "Invalid command line options\n";

sub usage {
    print <<'USAGE';

BU Researcher Returning Identity Detector

LIVE BORROWER DRY RUN:
  bu-researcher-rejoin-detect.pl --borrower 123

LIVE BORROWER APPLY:
  bu-researcher-rejoin-detect.pl --borrower 123 --apply

SYNTHETIC SELF TEST:
  bu-researcher-rejoin-detect.pl \
      --self-test \
      --test-name "Researcher Name" \
      --test-email "person@example.edu" \
      --test-orcid "0000-0000-0000-0000"

Default behaviour is READ ONLY.
No candidate is written unless --apply is supplied.

USAGE
}

if ($help) {
    usage();
    exit 0;
}

my $dbh = C4::Context->dbh;

# ------------------------------------------------------
# Normalizers
# ------------------------------------------------------

sub clean {
    my ($v) = @_;
    return '' unless defined $v;

    $v =~ s/^\s+|\s+$//g;
    $v =~ s/\s+/ /g;

    return $v;
}

sub norm_text {
    my ($v) = @_;
    $v = lc clean($v);

    $v =~ s/[^a-z0-9]+/ /g;
    $v =~ s/^\s+|\s+$//g;
    $v =~ s/\s+/ /g;

    return $v;
}

sub norm_email {
    my ($v) = @_;
    return lc clean($v);
}

sub norm_orcid {
    my ($v) = @_;
    $v = lc clean($v);

    $v =~ s#^https?://orcid\.org/##i;
    $v =~ s#^orcid:\s*##i;
    $v =~ s/\s+//g;

    return uc($v);
}

sub norm_identifier {
    my ($v) = @_;
    return lc clean($v);
}

# ------------------------------------------------------
# Input identity
# ------------------------------------------------------

my %input;

if ($selftest) {

    %input = (
        borrowernumber => undef,
        cardnumber     => '',
        employee_id    => clean($test_employee_id),
        name           => clean($test_name),
        email          => clean($test_email),
        orcid          => clean($test_orcid),
        scopus         => clean($test_scopus),
        wos            => clean($test_wos),
    );

}
elsif ($borrowernumber) {

    my $row = $dbh->selectrow_hashref(
        q{
            SELECT
                b.borrowernumber,
                b.cardnumber,
                b.firstname,
                b.surname,
                b.email,

                c.employee_id,
                c.orcid,
                c.scopus_author_id,
                c.researcher_id

            FROM borrowers b

            LEFT JOIN custom_profile_details c
              ON c.borrowernumber=b.borrowernumber

            WHERE b.borrowernumber=?
        },
        undef,
        $borrowernumber
    );

    die "Borrower $borrowernumber not found\n"
        unless $row;

    %input = (
        borrowernumber => $row->{borrowernumber},
        cardnumber     => clean($row->{cardnumber}),
        employee_id    => clean($row->{employee_id}),

        name => clean(
            join ' ',
            grep { defined($_) && clean($_) ne '' }
            ($row->{firstname},$row->{surname})
        ),

        email  => clean($row->{email}),
        orcid  => clean($row->{orcid}),
        scopus => clean($row->{scopus_author_id}),
        wos    => clean($row->{researcher_id}),
    );

}
else {
    usage();
    die "\nUse --borrower or --self-test\n";
}


print "============================================================\n";
print " BU RESEARCHER RETURNING IDENTITY DETECTOR\n";
print "============================================================\n";

print "Mode      : "
    . ($selftest ? "SELF-TEST" : "BORROWER")
    . ($apply ? " + APPLY" : " + DRY-RUN")
    . "\n";

print "Borrower  : "
    . (defined $input{borrowernumber}
        ? $input{borrowernumber}
        : 'SYNTHETIC')
    . "\n";

print "Name      : $input{name}\n";
print "Email     : $input{email}\n";
print "Employee  : $input{employee_id}\n";
print "ORCID     : $input{orcid}\n";
print "Scopus    : $input{scopus}\n";
print "WoS       : $input{wos}\n";

print "------------------------------------------------------------\n";

# ------------------------------------------------------
# Former candidate pool
# ------------------------------------------------------

my $former = $dbh->selectall_arrayref(
    q{
        SELECT
            p.researcher_uuid,
            p.canonical_name,
            p.lifecycle_status,

            l.borrowernumber AS old_borrowernumber,
            l.cardnumber,
            l.employee_id,
            l.institutional_email,

            c.orcid,
            c.scopus_author_id,
            c.researcher_id

        FROM researcher_persons p

        LEFT JOIN researcher_patron_links l
          ON l.researcher_uuid=p.researcher_uuid
         AND l.link_status='former'

        LEFT JOIN custom_profile_details c
          ON c.borrowernumber=l.borrowernumber

        WHERE p.lifecycle_status='former'

        ORDER BY p.canonical_name,l.id DESC
    },
    { Slice => {} }
);

if (!@{$former}) {
    print "No former researchers available for matching.\n";
    exit 0;
}

my @results;

for my $candidate (@{$former}) {

    my $score = 0;

    my %match = (
        orcid    => 0,
        scopus   => 0,
        wos      => 0,
        employee => 0,
        email    => 0,
        name     => 0,
    );

    # Persistent IDs dominate.
    if (
        norm_orcid($input{orcid}) ne ''
        &&
        norm_orcid($input{orcid})
            eq norm_orcid($candidate->{orcid})
    ) {
        $match{orcid}=1;
        $score += 50;
    }

    if (
        norm_identifier($input{scopus}) ne ''
        &&
        norm_identifier($input{scopus})
            eq norm_identifier($candidate->{scopus_author_id})
    ) {
        $match{scopus}=1;
        $score += 20;
    }

    if (
        norm_identifier($input{wos}) ne ''
        &&
        norm_identifier($input{wos})
            eq norm_identifier($candidate->{researcher_id})
    ) {
        $match{wos}=1;
        $score += 15;
    }

    # Explicit employee ID only.
    if (
        norm_identifier($input{employee_id}) ne ''
        &&
        norm_identifier($input{employee_id})
            eq norm_identifier($candidate->{employee_id})
    ) {
        $match{employee}=1;
        $score += 10;
    }

    # Email helps, but cannot independently auto-link.
    if (
        norm_email($input{email}) ne ''
        &&
        norm_email($input{email})
            eq norm_email($candidate->{institutional_email})
    ) {
        $match{email}=1;
        $score += 10;
    }

    # Exact normalized name is supporting evidence only.
    if (
        norm_text($input{name}) ne ''
        &&
        norm_text($input{name})
            eq norm_text($candidate->{canonical_name})
    ) {
        $match{name}=1;
        $score += 5;
    }

    # Maximum stored score is 100.
    $score=100 if $score > 100;

    # Decision policy:
    #
    # 1. High-confidence persistent-identifier evidence can produce a
    #    strong returning-researcher result.
    #
    # 2. Exact email + exact normalized name is sufficient to surface
    #    a candidate for librarian review, but never for auto-linking.
    #
    # 3. Other accumulated evidence reaching 40 also goes to review.
    #
    # 4. Weak evidence remains unresolved.
    #
    my $decision;

    if ($score >= 80) {
        $decision = 'STRONG_RETURNING_RESEARCHER';
    }
    elsif (
        ($match{email} && $match{name})
        || $score >= 40
    ) {
        $decision = 'MANUAL_REVIEW';
    }
    else {
        $decision = 'WEAK_OR_NO_MATCH';
    }

    my %evidence = (
        input => {
            name        => $input{name},
            email       => $input{email},
            employee_id => $input{employee_id},
            orcid       => norm_orcid($input{orcid}),
            scopus      => $input{scopus},
            wos         => $input{wos},
        },

        candidate => {
            researcher_uuid  => $candidate->{researcher_uuid},
            canonical_name   => $candidate->{canonical_name},
            old_borrowernumber => $candidate->{old_borrowernumber},
        },

        matches => \%match,
        score   => $score,
        decision => $decision,
    );

    push @results, {
        researcher_uuid   => $candidate->{researcher_uuid},
        canonical_name    => $candidate->{canonical_name},
        old_borrowernumber=> $candidate->{old_borrowernumber},
        score             => $score,
        decision          => $decision,
        match             => \%match,
        evidence_json     => encode_json(\%evidence),
    };
}

@results = sort {
       $b->{score} <=> $a->{score}
    || $a->{canonical_name} cmp $b->{canonical_name}
} @results;


print "\nCANDIDATE RESULTS\n";
print "============================================================\n";

for my $r (@results) {

    printf(
        "%-24s score=%3d decision=%s\n",
        $r->{canonical_name},
        $r->{score},
        $r->{decision}
    );

    print "  UUID       : $r->{researcher_uuid}\n";
    print "  Old borrower: "
        . ($r->{old_borrowernumber} // '')
        . "\n";

    print "  Evidence   : "
        . "ORCID=$r->{match}->{orcid} "
        . "Scopus=$r->{match}->{scopus} "
        . "WoS=$r->{match}->{wos} "
        . "Employee=$r->{match}->{employee} "
        . "Email=$r->{match}->{email} "
        . "Name=$r->{match}->{name}\n";

    print "\n";
}


my $best = $results[0];

print "============================================================\n";
print " BEST CANDIDATE\n";
print "============================================================\n";

print "Researcher : $best->{canonical_name}\n";
print "UUID       : $best->{researcher_uuid}\n";
print "Score      : $best->{score}\n";
print "Decision   : $best->{decision}\n";


# ------------------------------------------------------
# Apply creates review candidate only.
# It NEVER merges/reconnects automatically.
# ------------------------------------------------------

if ($apply) {

    die "--apply requires a real --borrower\n"
        unless defined $input{borrowernumber};

    # Store any candidate whose final decision requires review.
    #
    # Important:
    # Exact name + exact email can legitimately produce
    # MANUAL_REVIEW even when the numeric score is below 40.
    #
    # Only WEAK_OR_NO_MATCH is ignored.
    #
    if (
        ($best->{decision} // '')
            eq 'WEAK_OR_NO_MATCH'
    ) {
        print "\nNo candidate stored: evidence is too weak.\n";
        exit 0;
    }

    my $exists = $dbh->selectrow_array(
        q{
            SELECT COUNT(*)
            FROM researcher_patron_links
            WHERE borrowernumber=?
        },
        undef,
        $input{borrowernumber}
    );

    if ($exists) {
        print "\nBorrower already belongs to a permanent researcher identity.\n";
        print "No rejoin candidate created.\n";
        exit 0;
    }

    my $evidence_hash = sha256_hex($best->{evidence_json});

    $dbh->do(
        q{
            INSERT INTO researcher_rejoin_candidates
            (
                new_borrowernumber,
                candidate_researcher_uuid,

                orcid_match,
                scopus_match,
                wos_match,
                email_match,
                name_match,

                confidence_score,
                evidence_json,
                review_status,
                created_at
            )
            VALUES
            (
                ?,?,
                ?,?,?,?,?,
                ?,?,
                'pending',
                NOW()
            )

            ON DUPLICATE KEY UPDATE
                orcid_match=VALUES(orcid_match),
                scopus_match=VALUES(scopus_match),
                wos_match=VALUES(wos_match),
                email_match=VALUES(email_match),
                name_match=VALUES(name_match),

                confidence_score=VALUES(confidence_score),
                evidence_json=VALUES(evidence_json),
                review_status='pending',
                reviewed_by=NULL,
                reviewed_at=NULL
        },
        undef,

        $input{borrowernumber},
        $best->{researcher_uuid},

        $best->{match}->{orcid},
        $best->{match}->{scopus},
        $best->{match}->{wos},
        $best->{match}->{email},
        $best->{match}->{name},

        $best->{score},
        $best->{evidence_json}
    );

    print "\nREJOIN REVIEW CANDIDATE STORED\n";
    print "Evidence SHA256: $evidence_hash\n";
    print "No identity was merged automatically.\n";
}

print "\nREJOIN_DETECTOR_OK\n";
