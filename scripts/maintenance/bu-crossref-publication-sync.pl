#!/usr/bin/perl

use Modern::Perl;

use C4::Context;
use HTTP::Request;
use JSON::MaybeXS qw(decode_json encode_json);
use LWP::UserAgent;
use URI::Escape qw(uri_escape_utf8);
use Time::HiRes qw(sleep);
use Getopt::Long qw(GetOptions);

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $apply = 0;
my $limit = 0;
my $publication_id = 0;

GetOptions(
    'apply'            => \$apply,
    'limit=i'          => \$limit,
    'publication-id=i' => \$publication_id,
) or die "Invalid arguments\n";

my $dbh = C4::Context->dbh;

die "Koha database connection unavailable\n"
    unless $dbh;

sub clean {
    my ($value) = @_;
    return '' unless defined $value;

    $value = "$value";
    $value =~ s/^\s+|\s+$//g;

    return $value;
}

sub normalize_doi {
    my ($doi) = @_;

    $doi = lc clean($doi);

    $doi =~ s{^https?://(?:dx\.)?doi\.org/}{};
    $doi =~ s/^doi:\s*//;
    $doi =~ s/\s+//g;
    $doi =~ s/[.,;]+$//;

    return $doi;
}

sub normalize_title {
    my ($title) = @_;

    $title = lc clean($title);
    $title =~ s/&amp;/ and /g;
    $title =~ s/[^a-z0-9]+/ /g;
    $title =~ s/\s+/ /g;
    $title =~ s/^\s+|\s+$//g;

    return $title;
}

sub token_similarity {
    my ($left, $right) = @_;

    $left  = normalize_title($left);
    $right = normalize_title($right);

    return 0 unless length($left) && length($right);
    return 1 if $left eq $right;

    my %left_tokens =
        map { $_ => 1 }
        grep { length($_) > 1 }
        split /\s+/, $left;

    my %right_tokens =
        map { $_ => 1 }
        grep { length($_) > 1 }
        split /\s+/, $right;

    my $intersection = 0;
    my $union = 0;

    my %all = (%left_tokens, %right_tokens);

    for my $token (keys %all) {
        $union++;

        $intersection++
            if $left_tokens{$token}
            && $right_tokens{$token};
    }

    return 0 unless $union;

    return $intersection / $union;
}

sub first_value {
    my ($value) = @_;

    return '' unless defined $value;

    if (ref($value) eq 'ARRAY') {
        return '' unless @{$value};
        return first_value($value->[0]);
    }

    if (ref($value) eq 'HASH') {
        for my $key (
            qw(
                value
                name
                title
                source
                publisher
            )
        ) {
            return first_value($value->{$key})
                if exists $value->{$key};
        }

        return '';
    }

    return clean($value);
}

sub crossref_year {
    my ($message) = @_;

    for my $field (
        qw(
            published-print
            published-online
            published
            issued
            created
        )
    ) {
        my $value = $message->{$field};

        next unless ref($value) eq 'HASH';

        my $date_parts = $value->{'date-parts'};

        next unless ref($date_parts) eq 'ARRAY';
        next unless ref($date_parts->[0]) eq 'ARRAY';

        my $year = $date_parts->[0][0];

        return $year
            if defined $year
            && $year =~ /^\d{4}$/;
    }

    return undef;
}

sub crossref_lookup {
    my ($doi) = @_;

    my $encoded = uri_escape_utf8($doi);

    my $url =
        "https://api.crossref.org/works/$encoded";

    my $ua = LWP::UserAgent->new(
        timeout => 35,
        agent   =>
            'BU-Koha-RIMS-Crossref/1.0 '
            . '(mailto:library@example.edu)',
    );

    my $request = HTTP::Request->new(
        GET => $url
    );

    $request->header(
        Accept => 'application/json'
    );

    my $response = $ua->request($request);

    return (
        undef,
        $response->code,
        $response->status_line
    ) unless $response->is_success;

    my $payload;

    eval {
        $payload =
            decode_json(
                $response->decoded_content
            );
    };

    if ($@ || ref($payload) ne 'HASH') {
        return (
            undef,
            $response->code,
            'Invalid Crossref JSON response'
        );
    }

    return (
        $payload,
        $response->code,
        ''
    );
}

my @conditions = (
    q{
        doi IS NOT NULL
        AND TRIM(doi) <> ''
    }
);

my @bind;

if ($publication_id) {
    push @conditions, 'id = ?';
    push @bind, $publication_id;
}

my $sql = q{
    SELECT
        id,
        publication_key,
        doi,
        title,
        journal,
        publication_year,
        document_type
    FROM researcher_publications_master
    WHERE
} . join(' AND ', @conditions)
  . ' ORDER BY id';

$sql .= ' LIMIT ' . int($limit)
    if $limit && $limit > 0;

my $publications =
    $dbh->selectall_arrayref(
        $sql,
        { Slice => {} },
        @bind
    );

my $found = scalar @{$publications};

my $job_id;

if ($apply) {
    $dbh->do(
        q{
            INSERT INTO researcher_sync_jobs
            (
                borrowernumber,
                source_name,
                job_type,
                job_status,
                records_found,
                metadata_json
            )
            VALUES
            (
                NULL,
                'crossref',
                'manual',
                'running',
                ?,
                ?
            )
        },
        undef,
        $found,
        encode_json({
            mode => 'existing_doi_verification',
            automatic_doi_insertion => 0,
            publication_id_filter =>
                $publication_id || undef,
            limit => $limit || undef,
        })
    );

    $job_id = $dbh->{mysql_insertid};
}

my %summary = (
    found                => $found,
    processed            => 0,
    verified             => 0,
    inserted             => 0,
    updated              => 0,
    held                 => 0,
    not_found            => 0,
    lookup_failed        => 0,
    doi_mismatch         => 0,
    title_mismatch       => 0,
    database_changes     =>
        $apply
        ? 'CROSSREF_SOURCE_ROWS_ONLY'
        : 'NONE',
    publication_doi_changes => 0,
);

my @results;

eval {
    $dbh->{AutoCommit} = 0
        if $apply;

    for my $publication (@{$publications}) {
        my $local_doi =
            normalize_doi(
                $publication->{doi}
            );

        print "\n";
        print "Publication ID: $publication->{id}\n";
        print "DOI:            $local_doi\n";
        print "Title:          $publication->{title}\n";

        my (
            $payload,
            $http_code,
            $error
        ) = crossref_lookup($local_doi);

        $summary{processed}++;

        if (!$payload) {
            if ($http_code == 404) {
                $summary{not_found}++;
            }
            else {
                $summary{lookup_failed}++;
            }

            push @results, {
                publication_id => $publication->{id},
                doi            => $local_doi,
                decision       =>
                    $http_code == 404
                    ? 'not_found'
                    : 'lookup_failed',
                http_code      => $http_code,
                error          => $error,
            };

            print "Decision:       HOLD ($error)\n";

            sleep 0.25;
            next;
        }

        my $message =
            $payload->{message};

        unless (ref($message) eq 'HASH') {
            $summary{lookup_failed}++;

            push @results, {
                publication_id => $publication->{id},
                doi            => $local_doi,
                decision       => 'lookup_failed',
                error          =>
                    'Crossref message missing',
            };

            print "Decision:       HOLD (message missing)\n";

            sleep 0.25;
            next;
        }

        my $crossref_doi =
            normalize_doi(
                $message->{DOI}
            );

        my $crossref_title =
            first_value(
                $message->{title}
            );

        my $crossref_journal =
            first_value(
                $message->{'container-title'}
            );

        my $crossref_publisher =
            first_value(
                $message->{publisher}
            );

        my $crossref_year =
            crossref_year($message);

        my $similarity =
            token_similarity(
                $publication->{title},
                $crossref_title
            );

        my $doi_exact =
            $local_doi
            && $crossref_doi
            && $local_doi eq $crossref_doi
            ? 1 : 0;

        my $title_safe =
            $similarity >= 0.72
            ? 1 : 0;

        my $year_safe = 1;

        if (
            $publication->{publication_year}
            && $crossref_year
        ) {
            my $difference =
                abs(
                    $publication->{publication_year}
                    - $crossref_year
                );

            $year_safe =
                $difference <= 1
                ? 1 : 0;
        }

        my $decision =
            $doi_exact
            && $title_safe
            && $year_safe
            ? 'verified'
            : 'hold_for_manual_review';

        if (!$doi_exact) {
            $summary{doi_mismatch}++;
        }

        if (!$title_safe) {
            $summary{title_mismatch}++;
        }

        my $citation_count =
            $message->{'is-referenced-by-count'};

        $citation_count = undef
            unless defined $citation_count
            && "$citation_count" =~ /^\d+$/;

        my $source_url =
            clean($message->{URL});

        $source_url =
            "https://doi.org/$crossref_doi"
            unless $source_url =~ m{^https?://}i;

        my $verification = {
            decision          => $decision,
            verified_at       => scalar localtime(),
            doi_exact         => $doi_exact,
            title_similarity  =>
                sprintf('%.4f', $similarity) + 0,
            year_safe         => $year_safe,
            local_title       =>
                $publication->{title},
            crossref_title    =>
                $crossref_title,
            local_journal     =>
                $publication->{journal},
            crossref_journal  =>
                $crossref_journal,
            crossref_publisher =>
                $crossref_publisher,
            local_year        =>
                $publication->{publication_year},
            crossref_year     =>
                $crossref_year,
            policy            =>
                'existing DOI only; no DOI insertion',
        };

        push @results, {
            publication_id => $publication->{id},
            doi            => $local_doi,
            decision       => $decision,
            %{$verification},
        };

        if ($decision eq 'verified') {
            $summary{verified}++;

            if ($apply) {
                my ($existing_id) =
                    $dbh->selectrow_array(
                        q{
                            SELECT id
                            FROM researcher_publication_sources
                            WHERE source_name = 'crossref'
                              AND source_record_id = ?
                            LIMIT 1
                        },
                        undef,
                        $crossref_doi
                    );

                my %stored_message = %{$message};

                $stored_message{
                    '_rims_verification'
                } = $verification;

                $dbh->do(
                    q{
                        INSERT INTO
                            researcher_publication_sources
                        (
                            publication_id,
                            source_name,
                            source_record_id,
                            source_url,
                            citation_count,
                            raw_json,
                            first_seen_at,
                            last_synced_at
                        )
                        VALUES
                        (
                            ?,
                            'crossref',
                            ?,
                            ?,
                            ?,
                            ?,
                            NOW(),
                            NOW()
                        )
                        ON DUPLICATE KEY UPDATE
                            publication_id =
                                VALUES(publication_id),
                            source_url =
                                VALUES(source_url),
                            citation_count =
                                VALUES(citation_count),
                            raw_json =
                                VALUES(raw_json),
                            last_synced_at =
                                NOW()
                    },
                    undef,
                    $publication->{id},
                    $crossref_doi,
                    $source_url,
                    $citation_count,
                    encode_json(\%stored_message)
                );

                if ($existing_id) {
                    $summary{updated}++;
                }
                else {
                    $summary{inserted}++;
                }
            }

            print "Decision:       VERIFIED\n";
        }
        else {
            $summary{held}++;

            print "Decision:       HOLD FOR MANUAL REVIEW\n";
        }

        printf(
            "Title score:     %.4f\n",
            $similarity
        );

        print "Crossref title: $crossref_title\n";
        print "Crossref venue: $crossref_journal\n";
        print "Crossref year:  ",
            defined $crossref_year
            ? $crossref_year
            : '',
            "\n";

        sleep 0.25;
    }

    if ($apply) {
        $dbh->do(
            q{
                UPDATE researcher_sync_jobs
                SET
                    job_status = 'completed',
                    completed_at = NOW(),
                    records_processed = ?,
                    records_added = ?,
                    records_updated = ?,
                    records_linked = 0,
                    metadata_json = ?
                WHERE id = ?
            },
            undef,
            $summary{processed},
            $summary{inserted},
            $summary{updated},
            encode_json({
                summary => \%summary,
                results => \@results,
            }),
            $job_id
        );

        $dbh->commit;
        $dbh->{AutoCommit} = 1;
    }
};

if ($@) {
    my $failure = "$@";
    $failure =~ s/\s+$//;

    if ($apply) {
        eval {
            $dbh->rollback
                unless $dbh->{AutoCommit};
        };

        $dbh->{AutoCommit} = 1;

        if ($job_id) {
            $dbh->do(
                q{
                    UPDATE researcher_sync_jobs
                    SET
                        job_status = 'failed',
                        completed_at = NOW(),
                        error_message = ?
                    WHERE id = ?
                },
                undef,
                $failure,
                $job_id
            );
        }
    }

    die "CROSSREF_SYNC_FAILED: $failure\n";
}

print "\n";
print "============================================================\n";
print " CROSSREF SYNC SUMMARY\n";
print "============================================================\n";

for my $key (
    qw(
        found
        processed
        verified
        inserted
        updated
        held
        not_found
        lookup_failed
        doi_mismatch
        title_mismatch
        publication_doi_changes
        database_changes
    )
) {
    print "$key=$summary{$key}\n";
}

print "============================================================\n";

exit 0;
