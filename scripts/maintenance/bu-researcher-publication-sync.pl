#!/usr/bin/perl

use Modern::Perl;

use C4::Context;
use Digest::SHA qw(sha256_hex);
use HTTP::Request;
use JSON qw(decode_json encode_json);
use LWP::UserAgent;
use URI::Escape qw(uri_escape_utf8);

my $instance = shift @ARGV || $ENV{KOHA_INSTANCE} || 'INSTANCE';
my $only_borrowernumber = shift @ARGV || '';

if (
    $only_borrowernumber ne ''
    && $only_borrowernumber !~ /^\d+$/
) {
    die "Invalid borrowernumber\n";
}

my $env_file =
    "/etc/koha/sites/$instance/research-api.env";

sub read_env_file {
    my ($file) = @_;

    my %env;

    open my $fh, '<', $file
        or die "Cannot open API environment file: $file\n";

    while (my $line = <$fh>) {
        chomp $line;

        next if $line =~ /^\s*#/;
        next if $line =~ /^\s*$/;

        if (
            $line =~
            /^\s*([A-Z0-9_]+)\s*=\s*"(.*)"\s*$/
        ) {
            $env{$1} = $2;
        }
        elsif (
            $line =~
            /^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/
        ) {
            $env{$1} = $2;
        }
    }

    close $fh;
    return %env;
}

my %api_env = read_env_file($env_file);

my $scopus_api_key =
    $api_env{SCOPUS_API_KEY} || '';

die "Scopus API key missing\n"
    unless $scopus_api_key;

my $page_size =
    $api_env{SCOPUS_PAGE_SIZE} || 25;

my $max_records =
    $api_env{SCOPUS_MAX_RECORDS} || 300;

$page_size = 25 if $page_size > 25;
$page_size = 1  if $page_size < 1;

$max_records = 300
    if $max_records < 1;

my $dbh = C4::Context->dbh;

sub trim {
    my ($value) = @_;

    $value = '' unless defined $value;
    $value = "$value";

    $value =~ s/^\s+//;
    $value =~ s/\s+$//;

    return $value;
}

sub normalise_doi {
    my ($doi) = @_;

    $doi = lc trim($doi);

    $doi =~ s{^https?://(?:dx\.)?doi\.org/}{};
    $doi =~ s{^doi:\s*}{};
    $doi =~ s/\s+//g;

    return $doi;
}

sub normalise_title {
    my ($title) = @_;

    $title = lc trim($title);

    $title =~ s/&amp;/ and /g;
    $title =~ s/[^a-z0-9]+/ /g;
    $title =~ s/\s+/ /g;
    $title =~ s/^\s+|\s+$//g;

    return $title;
}

sub publication_key {
    my (%args) = @_;

    my $doi = normalise_doi($args{doi});

    return "doi:$doi"
        if $doi ne '';

    my $normalised_title =
        normalise_title($args{title});

    my $year = trim($args{year});
    my $journal = normalise_title($args{journal});

    return 'meta:' . sha256_hex(
        join(
            '|',
            $normalised_title,
            $year,
            $journal
        )
    );
}

sub parse_year {
    my ($date) = @_;

    $date = trim($date);

    return $1
        if $date =~ /^(\d{4})/;

    return undef;
}

sub parse_date {
    my ($date) = @_;

    $date = trim($date);

    return $date
        if $date =~ /^\d{4}-\d{2}-\d{2}$/;

    return "$1-01-01"
        if $date =~ /^(\d{4})$/;

    return undef;
}

sub scopus_record_id {
    my ($entry) = @_;

    my $eid = trim($entry->{eid});

    return $eid
        if $eid ne '';

    my $identifier =
        trim($entry->{'dc:identifier'});

    return $identifier
        if $identifier ne '';

    my $url = trim($entry->{'prism:url'});

    return $url
        if $url ne '';

    return '';
}

sub scopus_web_url {
    my ($entry) = @_;

    my $eid = trim($entry->{eid});

    if ($eid =~ /2-s2\.0-(\d+)/) {
        return
            'https://www.scopus.com/inward/'
            . 'record.uri?partnerID=HzOxMe3b'
            . '&scp=' . $1
            . '&origin=inward';
    }

    return trim($entry->{'prism:url'});
}

sub fetch_scopus_page {
    my (%args) = @_;

    my $query =
        'AU-ID(' . $args{scopus_id} . ')';

    my $url =
          'https://api.elsevier.com/content/search/scopus'
        . '?query='
        . uri_escape_utf8($query)
        . '&count='
        . uri_escape_utf8($args{count})
        . '&start='
        . uri_escape_utf8($args{start})
        . '&sort=-coverDate'
        . '&view=STANDARD'
        . '&httpAccept=application/json';

    my $ua = LWP::UserAgent->new(
        timeout => 60,
        agent   => 'BU-Koha-Researcher-Sync/1.0'
    );

    my $request =
        HTTP::Request->new(GET => $url);

    $request->header(
        'Accept' => 'application/json'
    );

    $request->header(
        'X-ELS-APIKey' => $scopus_api_key
    );

    my $response = $ua->request($request);

    if (!$response->is_success) {
        die 'Scopus API error: '
            . $response->status_line
            . "\n";
    }

    my $json;

    eval {
        $json = decode_json(
            $response->decoded_content
        );
    };

    if ($@) {
        die "Scopus JSON parse error\n";
    }

    return $json;
}

# RIMS_SCOPUS_AUTHORITATIVE_IDENTIFIER_GATE_V1
my @where = (
    q{c.verification_status = 'verified'},
    q{c.employment_status = 'active'},
    q{c.sync_enabled = 1},
    q{COALESCE(c.scopus_author_id, '') <> ''}
);

my @bind;

if ($only_borrowernumber ne '') {
    push @where, q{c.borrowernumber = ?};
    push @bind, $only_borrowernumber;
}

my $researchers =
    $dbh->selectall_arrayref(
        '
        SELECT
            c.borrowernumber,
            c.preferred_name,
            c.official_name,
            c.scopus_author_id,
            c.main_affiliation,
            c.affiliation_start,
            c.affiliation_end
        FROM custom_profile_details c
        INNER JOIN researcher_identifiers ri
            ON ri.borrowernumber = c.borrowernumber
           AND ri.identifier_type = "scopus"
           AND ri.verification_status = "verified"
           AND ri.is_primary = 1
           AND ri.is_active = 1
           AND TRIM(ri.identifier_value) =
               TRIM(c.scopus_author_id)
        WHERE '
        . join(' AND ', @where)
        . '
        ORDER BY c.borrowernumber
        ',
        { Slice => {} },
        @bind
    ) || [];

if (!@$researchers) {
    print "No eligible verified active Scopus profiles found.\n";
    exit 0;
}

for my $researcher (@$researchers) {

    my $borrowernumber =
        $researcher->{borrowernumber};

    my $scopus_id =
        trim($researcher->{scopus_author_id});

    my $job_id;

    eval {
        $dbh->do(
            q{
                INSERT INTO researcher_sync_jobs
                (
                    borrowernumber,
                    source_name,
                    job_type,
                    job_status
                )
                VALUES (?, 'scopus', ?, 'running')
            },
            undef,
            $borrowernumber,
            $only_borrowernumber ne ''
                ? 'manual'
                : 'scheduled'
        );

        $job_id = $dbh->{mysql_insertid};

        my @entries;
        my $start = 0;
        my $total = 0;

        while (@entries < $max_records) {

            my $json = fetch_scopus_page(
                scopus_id => $scopus_id,
                count      => $page_size,
                start      => $start,
            );

            my $search_results =
                $json->{'search-results'} || {};

            $total =
                $search_results
                    ->{'opensearch:totalResults'}
                || 0;

            my $page_entries =
                $search_results->{entry} || [];

            last
                unless ref($page_entries) eq 'ARRAY'
                && @$page_entries;

            for my $entry (@$page_entries) {
                next
                    if $entry->{error};

                push @entries, $entry;

                last
                    if @entries >= $max_records;
            }

            $start += $page_size;

            last
                if $start >= $total;

            last
                if $start > 5000;
        }

        my $records_added = 0;
        my $records_updated = 0;
        my $records_linked = 0;
        my $records_processed = 0;

        # RIMS_SCOPUS_CURRENT_SET_RECONCILIATION_V2
        #
        # Track the complete set of publications returned by the
        # current Scopus Author-ID synchronization.
        my %current_scopus_publication_ids;


        $dbh->{AutoCommit} = 0;

        for my $entry (@entries) {

            my $title =
                trim($entry->{'dc:title'});

            next
                if $title eq '';

            my $journal =
                trim(
                    $entry
                        ->{'prism:publicationName'}
                );

            my $date =
                trim($entry->{'prism:coverDate'});

            my $doi =
                normalise_doi(
                    $entry->{'prism:doi'}
                );

            my $eid =
                scopus_record_id($entry);

            next
                if $eid eq '';

            my $year =
                parse_year($date);

            my $publication_date =
                parse_date($date);

            my $document_type =
                trim(
                    $entry
                        ->{'subtypeDescription'}
                );

            my $citation_count =
                trim(
                    $entry
                        ->{'citedby-count'}
                );

            $citation_count = undef
                unless defined $citation_count
                && $citation_count =~ /^\d+$/;

            my $pub_key = publication_key(
                doi     => $doi,
                title   => $title,
                year    => $year,
                journal => $journal,
            );

            my $existing_publication_id =
                $dbh->selectrow_array(
                    q{
                        SELECT id
                        FROM researcher_publications_master
                        WHERE publication_key = ?
                    },
                    undef,
                    $pub_key
                );

            $dbh->do(
                q{
                    INSERT INTO
                        researcher_publications_master
                    (
                        publication_key,
                        doi,
                        normalised_doi,
                        title,
                        normalised_title,
                        journal,
                        publication_date,
                        publication_year,
                        document_type
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        doi = VALUES(doi),
                        normalised_doi =
                            VALUES(normalised_doi),
                        title = VALUES(title),
                        normalised_title =
                            VALUES(normalised_title),
                        journal = VALUES(journal),
                        publication_date =
                            VALUES(publication_date),
                        publication_year =
                            VALUES(publication_year),
                        document_type =
                            VALUES(document_type),
                        updated_at = NOW()
                },
                undef,
                $pub_key,
                $doi || undef,
                $doi || undef,
                $title,
                normalise_title($title),
                $journal || undef,
                $publication_date,
                $year,
                $document_type || undef
            );

            my $publication_id =
                $dbh->selectrow_array(
                    q{
                        SELECT id
                        FROM researcher_publications_master
                        WHERE publication_key = ?
                    },
                    undef,
                    $pub_key
                );

            if ($existing_publication_id) {
                $records_updated++;
            }
            else {
                $records_added++;
            }

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
                        last_synced_at
                    )
                    VALUES (
                        ?,
                        'scopus',
                        ?,
                        ?,
                        ?,
                        ?,
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
                        last_synced_at = NOW()
                },
                undef,
                $publication_id,
                $eid,
                scopus_web_url($entry),
                $citation_count,
                encode_json($entry)
            );

            # Present in this current authoritative API result set.
            $current_scopus_publication_ids{$publication_id} = 1;

            my $existing_link =
                $dbh->selectrow_array(
                    q{
                        SELECT id
                        FROM researcher_publication_links
                        WHERE borrowernumber = ?
                          AND publication_id = ?
                          AND source_name = 'scopus'
                    },
                    undef,
                    $borrowernumber,
                    $publication_id
                );

            $dbh->do(
                q{
                    INSERT INTO
                        researcher_publication_links
                    (
                        borrowernumber,
                        publication_id,
                        source_name,
                        source_author_id,
                        affiliation_status,
                        match_score,
                        system_decision,
                        review_status,
                        last_confirmed_at
                    )
                    VALUES (
                        ?,
                        ?,
                        'scopus',
                        ?,
                        'source_author_id_match',
                        100.00,
                        'confirmed',
                        'auto_confirmed',
                        NOW()
                    )
                    ON DUPLICATE KEY UPDATE
                        source_author_id =
                            VALUES(source_author_id),
                        affiliation_status =
                            VALUES(affiliation_status),
                        match_score =
                            VALUES(match_score),
                        system_decision =
                            VALUES(system_decision),
                        review_status =
                            CASE
                                WHEN review_status =
                                    'manually_rejected'
                                THEN review_status
                                ELSE
                                    VALUES(review_status)
                            END,
                        last_confirmed_at = NOW()
                },
                undef,
                $borrowernumber,
                $publication_id,
                $scopus_id
            );

            $records_linked++
                unless $existing_link;

            $records_processed++;
        }


        # =====================================================
        # RIMS_SCOPUS_CURRENT_SET_RECONCILIATION_V2
        #
        # Only a COMPLETE successful API result set is allowed
        # to change previous researcher-publication membership.
        #
        # Master publication and source provenance are preserved.
        # =====================================================

        my @current_scopus_pub_ids =
            sort { $a <=> $b }
            keys %current_scopus_publication_ids;

        my $current_distinct_count =
            scalar(@current_scopus_pub_ids);

        my $reconciliation_safe =
               defined($total)
            && $total >= 0
            && $records_processed == $total
            && $current_distinct_count == $total;

        if ($reconciliation_safe) {

            my $stale_sql = q{
                SELECT
                    id,
                    publication_id
                FROM researcher_publication_links
                WHERE borrowernumber = ?
                  AND source_name = 'scopus'
                  AND source_author_id = ?
                  AND system_decision = 'confirmed'
            };

            my @stale_bind = (
                $borrowernumber,
                $scopus_id
            );

            if (@current_scopus_pub_ids) {

                my $ph =
                    join(
                        ',',
                        ('?') x @current_scopus_pub_ids
                    );

                $stale_sql .=
                    " AND publication_id NOT IN ($ph)";

                push @stale_bind,
                    @current_scopus_pub_ids;
            }

            my $stale_links =
                $dbh->selectall_arrayref(
                    $stale_sql,
                    { Slice => {} },
                    @stale_bind
                );

            for my $stale (@{$stale_links || []}) {

                my $link_id =
                    $stale->{id};

                my $publication_id =
                    $stale->{publication_id};

                # RETIRE rather than destroy.
                #
                # The historical link remains auditable but no
                # longer contributes to confirmed/current output.
                $dbh->do(
                    q{
                        UPDATE researcher_publication_links
                        SET
                            affiliation_status = 'needs_review',
                            match_score = 0.00,
                            system_decision = 'review',
                            review_status = 'needs_review',
                            reviewed_by = NULL,
                            reviewed_at = NULL
                        WHERE id = ?
                          AND borrowernumber = ?
                          AND source_name = 'scopus'
                          AND source_author_id = ?
                          AND system_decision = 'confirmed'
                    },
                    undef,
                    $link_id,
                    $borrowernumber,
                    $scopus_id
                );

                $dbh->do(
                    q{
                        INSERT INTO researcher_audit_log
                        (
                            borrowernumber,
                            action_type,
                            old_value,
                            new_value,
                            action_reason,
                            source
                        )
                        VALUES
                        (
                            ?,
                            'scopus_link_retired',
                            ?,
                            ?,
                            'Publication absent from complete current Scopus Author-ID result set',
                            'sync'
                        )
                    },
                    undef,
                    $borrowernumber,

                    'link_id='
                        . $link_id
                        . '; publication_id='
                        . $publication_id
                        . '; system_decision=confirmed',

                    'link_id='
                        . $link_id
                        . '; publication_id='
                        . $publication_id
                        . '; system_decision=review'
                );
            }

            print STDERR
                'SCOPUS_RECONCILIATION_OK'
                . ' | borrowernumber='
                . $borrowernumber
                . ' | scopus_author_id='
                . $scopus_id
                . ' | api_total='
                . $total
                . ' | processed='
                . $records_processed
                . ' | current_distinct='
                . $current_distinct_count
                . ' | retired='
                . scalar(@{$stale_links || []})
                . "\n";
        }
        else {

            # Fail closed:
            # incomplete API response must NEVER retire data.
            print STDERR
                'SCOPUS_RECONCILIATION_SKIPPED'
                . ' | borrowernumber='
                . $borrowernumber
                . ' | scopus_author_id='
                . $scopus_id
                . ' | api_total='
                . (
                    defined($total)
                    ? $total
                    : 'NULL'
                )
                . ' | processed='
                . $records_processed
                . ' | current_distinct='
                . $current_distinct_count
                . "\n";
        }

        $dbh->do(
            q{
                UPDATE custom_profile_details
                SET
                    last_scopus_sync = NOW(),
                    identity_confidence =
                        CASE
                            WHEN identity_confidence IS NULL
                            THEN 100.00
                            ELSE identity_confidence
                        END,
                    identity_decision =
                        CASE
                            WHEN identity_decision IS NULL
                            THEN 'verified_source_id'
                            ELSE identity_decision
                        END
                WHERE borrowernumber = ?
            },
            undef,
            $borrowernumber
        );

        $dbh->do(
            q{
                UPDATE researcher_sync_jobs
                SET
                    job_status = 'completed',
                    completed_at = NOW(),
                    records_found = ?,
                    records_processed = ?,
                    records_added = ?,
                    records_updated = ?,
                    records_linked = ?,
                    metadata_json = ?
                WHERE id = ?
            },
            undef,
            $total,
            $records_processed,
            $records_added,
            $records_updated,
            $records_linked,
            encode_json(
                {
                    scopus_author_id =>
                        $scopus_id,
                    max_records =>
                        $max_records,
                    page_size =>
                        $page_size,
                }
            ),
            $job_id
        );

        $dbh->do(
            q{
                INSERT INTO researcher_audit_log
                (
                    borrowernumber,
                    action_type,
                    new_value,
                    action_reason,
                    source
                )
                VALUES (
                    ?,
                    'scopus_publications_synced',
                    ?,
                    'Scopus publication sync completed',
                    'sync'
                )
            },
            undef,
            $borrowernumber,
            join(
                '; ',
                "records_found=$total",
                "records_processed=$records_processed",
                "records_added=$records_added",
                "records_updated=$records_updated",
                "records_linked=$records_linked"
            )
        );

        $dbh->commit;
        $dbh->{AutoCommit} = 1;

        print join(
            ' | ',
            'SYNC_OK',
            'borrowernumber=' . $borrowernumber,
            'name='
                . (
                    $researcher->{preferred_name}
                    || ''
                ),
            'found=' . $total,
            'processed=' . $records_processed,
            'added=' . $records_added,
            'updated=' . $records_updated,
            'linked=' . $records_linked
        ) . "\n";
    };

    if ($@) {
        my $error = "$@";
        $error =~ s/\s+$//;

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
                $error,
                $job_id
            );
        }

        warn join(
            ' | ',
            'SYNC_FAILED',
            'borrowernumber='
                . $borrowernumber,
            'error=' . $error
        ) . "\n";
    }
}

exit 0;
