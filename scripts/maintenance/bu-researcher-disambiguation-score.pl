#!/usr/bin/perl

use Modern::Perl;
use C4::Context;

my $dbh = C4::Context->dbh;

my $instance = $ENV{KOHA_INSTANCE} || 'INSTANCE';
if ($ENV{KOHA_CONF} && $ENV{KOHA_CONF} =~ m{/etc/koha/sites/([^/]+)/koha-conf\.xml}) {
    $instance = $1;
}
my %runtime_env;
my $env_file = "/etc/koha/sites/$instance/research-api.env";
if (-f $env_file && open my $efh, '<', $env_file) {
    while (my $line = <$efh>) {
        chomp $line;
        next if $line =~ /^\s*(?:#|$)/;
        if ($line =~ /^([A-Z0-9_]+)=(.*)$/) {
            my ($k, $v) = ($1, $2);
            $v =~ s/^['"]|['"]$//g;
            $runtime_env{$k} = $v;
        }
    }
    close $efh;
}
my $institution_name = $ENV{RIMS_INSTITUTION_NAME}
    || $runtime_env{RIMS_INSTITUTION_NAME}
    || 'Example University';

sub trim {
    my ($value) = @_;

    $value = '' unless defined $value;
    $value = "$value";

    $value =~ s/^\s+//;
    $value =~ s/\s+$//;

    return $value;
}

sub normalise_name {
    my ($value) = @_;

    $value = lc trim($value);
    $value =~ s/[^a-z0-9]+/ /g;
    $value =~ s/\s+/ /g;
    $value =~ s/^\s+|\s+$//g;

    return $value;
}

sub contains_institution {
    my ($value) = @_;

    my $needle = lc trim($institution_name);
    return 0 if $needle eq '' || $needle =~ /^__/;

    return index(lc(trim($value)), $needle) >= 0 ? 1 : 0;
}

my $links = $dbh->selectall_arrayref(
    q{
        SELECT
            l.id,
            l.borrowernumber,
            l.publication_id,
            l.source_name,
            l.source_author_id,
            l.author_name,
            l.affiliation_status,
            l.match_score,
            l.system_decision,
            l.review_status,

            c.preferred_name,
            c.official_name,
            c.alternative_name,
            c.scopus_author_id,
            c.researcher_id,
            c.orcid,
            c.main_affiliation,
            c.affiliation_organisation,
            c.employment_status,
            c.verification_status,

            p.title,
            p.doi,
            p.publication_year

        FROM researcher_publication_links l

        JOIN custom_profile_details c
          ON c.borrowernumber = l.borrowernumber

        JOIN researcher_publications_master p
          ON p.id = l.publication_id
    },
    { Slice => {} }
) || [];

my $confirmed = 0;
my $reviewed  = 0;
my $rejected  = 0;

for my $row (@$links) {

    my $identifier_score = 0;
    my $name_score       = 0;
    my $affiliation_score = 0;
    my $timeline_score   = 0;

    my $source_author_id =
        trim($row->{source_author_id});

    # RIMS_DISAMBIGUATION_AUTHORITATIVE_IDENTIFIER_V1
    #
    # Identifier evidence is accepted only when the source author ID
    # exists as the researcher's verified, primary and active
    # authoritative identifier.
    my $identifier_type =
          $row->{source_name} eq 'scopus' ? 'scopus'
        : $row->{source_name} eq 'wos'    ? 'wos'
        : '';

    if (
        $identifier_type ne ''
        && $source_author_id ne ''
    ) {
        my ($authoritative_match) =
            $dbh->selectrow_array(
                q{
                    SELECT COUNT(*)
                    FROM researcher_identifiers
                    WHERE borrowernumber = ?
                      AND identifier_type = ?
                      AND identifier_value = ?
                      AND verification_status = 'verified'
                      AND is_primary = 1
                      AND is_active = 1
                },
                undef,
                $row->{borrowernumber},
                $identifier_type,
                $source_author_id
            );

        $identifier_score = 55
            if ($authoritative_match || 0) == 1;
    }

    my $candidate_name =
        normalise_name($row->{author_name});

    my @known_names = grep { $_ ne '' } map {
        normalise_name($_)
    } (
        $row->{preferred_name},
        $row->{official_name},
        $row->{alternative_name}
    );

    if ($candidate_name ne '') {
        for my $known (@known_names) {
            if ($candidate_name eq $known) {
                $name_score = 20;
                last;
            }

            if (
                index($candidate_name, $known) >= 0
                || index($known, $candidate_name) >= 0
            ) {
                $name_score = 12
                    if $name_score < 12;
            }
        }
    }

    if (
        contains_institution($row->{main_affiliation})
        || contains_institution(
            $row->{affiliation_organisation}
        )
    ) {
        $affiliation_score = 15;
    }

    if (
        ($row->{employment_status} || '') eq 'active'
        && defined $row->{publication_year}
    ) {
        $timeline_score = 10;
    }

    my $total =
          $identifier_score
        + $name_score
        + $affiliation_score
        + $timeline_score;

    my $decision;
    my $review_status;

    # RIMS_DISAMBIGUATION_SCORE_INTEGRITY_V2
    #
    # Preserve the evidence-derived score. A verified authoritative
    # identifier remains strong confirmation evidence, but the numeric
    # score is no longer inflated to 100.
    if ($identifier_score == 55) {
        $decision = 'confirmed';
        $review_status = 'auto_confirmed';
        $confirmed++;
    }
    elsif ($total >= 80) {
        $decision = 'confirmed';
        $review_status = 'auto_confirmed';
        $confirmed++;
    }
    elsif ($total >= 60) {
        $decision = 'review';
        $review_status = 'needs_review';
        $reviewed++;
    }
    else {
        $decision = 'review';
        $review_status = 'needs_review';
        $reviewed++;
    }

    next
        if ($row->{review_status} || '') eq
           'manually_rejected';

    next
        if ($row->{review_status} || '') eq
           'manually_confirmed';

    $dbh->do(
        q{
            UPDATE researcher_publication_links
            SET
                match_score = ?,
                system_decision = ?,
                review_status = ?,
                affiliation_status =
                    CASE
                        WHEN ? >= 15
                        THEN 'institution_affiliation_match'
                        WHEN affiliation_status =
                             'source_author_id_match'
                        THEN affiliation_status
                        ELSE 'affiliation_not_confirmed'
                    END
            WHERE id = ?
        },
        undef,
        $total,
        $decision,
        $review_status,
        $affiliation_score,
        $row->{id}
    );

    my ($existing_case_id) =
        $dbh->selectrow_array(
            q{
                SELECT id
                FROM researcher_disambiguation_cases
                WHERE borrowernumber = ?
                  AND source_name = ?
                  AND COALESCE(source_record_id, '') =
                      COALESCE(?, '')
                  AND COALESCE(doi, '') =
                      COALESCE(?, '')
                  AND reviewer_decision IS NULL
                ORDER BY id DESC
                LIMIT 1
            },
            undef,
            $row->{borrowernumber},
            $row->{source_name},
            $row->{source_author_id},
            $row->{doi}
        );

    if (!$existing_case_id) {
        $dbh->do(
        q{
            INSERT INTO researcher_disambiguation_cases
            (
                borrowernumber,
                source_name,
                source_record_id,
                doi,
                publication_title,
                candidate_author_name,
                candidate_affiliation,
                name_score,
                identifier_score,
                affiliation_score,
                timeline_score,
                total_score,
                system_decision,
                reviewer_decision,
                decision_reason,
                evidence_json
            )
            VALUES (
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                NULL,
                ?,
                NULL
            )
        },
        undef,
        $row->{borrowernumber},
        $row->{source_name},
        $row->{source_author_id},
        $row->{doi},
        $row->{title},
        $row->{author_name},
        $row->{main_affiliation},
        $name_score,
        $identifier_score,
        $affiliation_score,
        $timeline_score,
        $total,
        $decision,
        join(
            '; ',
            "identifier_score=$identifier_score",
            "name_score=$name_score",
            "affiliation_score=$affiliation_score",
            "timeline_score=$timeline_score"
        )
    );
    }
}

print join(
    ' | ',
    'DISAMBIGUATION_COMPLETE',
    'records=' . scalar(@$links),
    'confirmed=' . $confirmed,
    'review=' . $reviewed,
    'rejected=' . $rejected
) . "\n";

exit 0;
