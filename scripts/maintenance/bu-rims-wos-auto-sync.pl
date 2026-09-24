#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use C4::Context;
use LWP::UserAgent;
use HTTP::Request;
use JSON qw(decode_json encode_json);
use URI::Escape qw(uri_escape_utf8);
use Digest::MD5 qw(md5_hex);
use Digest::SHA qw(sha1_hex);
use Getopt::Long qw(GetOptions);
use File::Path qw(make_path);
use POSIX qw(strftime);

my $borrower;
my $all = 0;
my $force_api = 0;

GetOptions(
    'borrower=i' => \$borrower,
    'all'        => \$all,
    'force-api'  => \$force_api,
) or die "Invalid arguments\n";

die "Use --borrower NUMBER or --all\n"
    unless $all || ($borrower && $borrower =~ /^\d+$/);

my $instance = $ENV{KOHA_INSTANCE} || 'INSTANCE';

if (
       $ENV{KOHA_CONF}
    && $ENV{KOHA_CONF} =~ m{/etc/koha/sites/([^/]+)/koha-conf\.xml}
) {
    $instance = $1;
}

my $env_file =
    "/etc/koha/sites/$instance/research-api.env";

my $cache_dir =
    "/var/cache/koha/$instance/research-publications";

my $lock_dir =
    "/var/lock/koha/$instance";

my $log_file =
    "/var/log/koha/$instance/rims-wos-auto-sync.log";

make_path($cache_dir) unless -d $cache_dir;
make_path($lock_dir)  unless -d $lock_dir;

sub log_message {
    my ($message) = @_;

    my $timestamp =
        strftime('%Y-%m-%d %H:%M:%S', localtime);

    if (open my $fh, '>>', $log_file) {
        print {$fh} "[$timestamp] $message\n";
        close $fh;
    }

    print "[$timestamp] $message\n";
}

sub trim {
    my ($value) = @_;
    $value = '' unless defined $value;

    $value =~ s/^\s+//;
    $value =~ s/\s+$//;

    return $value;
}

sub normalize_orcid {
    my ($value) = @_;

    $value = trim($value);
    $value =~ s{^https?://orcid\.org/}{}i;
    $value =~ s/[^0-9Xx-]//g;

    return uc($value);
}

sub normalize_identifier {
    my ($value) = @_;

    $value = trim($value);
    $value =~ s/[^A-Za-z0-9-]//g;

    return $value;
}

sub normalize_doi {
    my ($value) = @_;

    $value = lc trim($value);

    $value =~ s{^https?://(?:dx\.)?doi\.org/}{}i;
    $value =~ s/^doi:\s*//i;
    $value =~ s/\s+//g;
    $value =~ s/[.,;]+$//;

    return $value;
}

sub normalize_title {
    my ($value) = @_;

    $value = lc trim($value);
    $value =~ s/&amp;/ and /g;
    $value =~ s/[^a-z0-9]+/ /g;
    $value =~ s/\s+/ /g;

    return trim($value);
}

sub read_env_file {
    my ($path) = @_;
    my %environment;

    return %environment unless -f $path;

    open my $fh, '<', $path
        or die "Unable to read $path: $!";

    while (my $line = <$fh>) {
        chomp $line;

        next if $line =~ /^\s*#/;
        next if $line =~ /^\s*$/;

        if (
            $line =~
            /^\s*([A-Z0-9_]+)\s*=\s*"(.*)"\s*$/
        ) {
            $environment{$1} = $2;
        }
        elsif (
            $line =~
            /^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/
        ) {
            $environment{$1} = $2;
        }
    }

    close $fh;

    return %environment;
}

my %api_env = read_env_file($env_file);

my $api_key =
       $api_env{WOS_API_KEY}
    || $api_env{CLARIVATE_API_KEY}
    || '';

my $database =
    $api_env{WOS_DB} || 'WOS';

my $page_size =
    $api_env{WOS_PAGE_SIZE} || 50;

my $max_records =
       $api_env{WOS_MAX_RECORDS}
    || $api_env{RECENT_LIMIT}
    || 300;

my $cache_ttl =
       $api_env{WOS_CACHE_TTL_SECONDS}
    || 86400;

$page_size = 50 if $page_size > 50;
$page_size = 1  if $page_size < 1;

$max_records = 300
    if $max_records < 1;

my $dbh = C4::Context->dbh;

sub table_exists {
    my ($table) = @_;

    return $dbh->selectrow_array(
        q{
            SELECT COUNT(*)
            FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = ?
        },
        undef,
        $table
    ) ? 1 : 0;
}

sub column_exists {
    my ($table, $column) = @_;

    return $dbh->selectrow_array(
        q{
            SELECT COUNT(*)
            FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = ?
              AND COLUMN_NAME = ?
        },
        undef,
        $table,
        $column
    ) ? 1 : 0;
}

sub first_existing_column {
    my ($table, @candidates) = @_;

    for my $column (@candidates) {
        return $column
            if column_exists($table, $column);
    }

    return '';
}

# RIMS_WOS_IDENTIFIER_FALLBACK_V11


for my $required_table (
    qw(
        researcher_identifiers
        researcher_publications_master
        researcher_publication_sources
        researcher_publication_links
        researcher_sync_jobs
    )
) {
    die "Required table missing: $required_table\n"
        unless table_exists($required_table);
}

sub read_json_file {
    my ($path) = @_;

    return unless -f $path;

    open my $fh, '<:encoding(UTF-8)', $path
        or return;

    local $/;
    my $text = <$fh>;
    close $fh;

    my $decoded;

    eval {
        $decoded = decode_json($text);
    };

    return $decoded;
}

sub write_json_file {
    my ($path, $value) = @_;

    my $temporary = "$path.tmp.$$";

    open my $fh, '>:encoding(UTF-8)', $temporary
        or die "Unable to write $temporary: $!";

    print {$fh} encode_json($value);
    close $fh;

    rename $temporary, $path
        or die "Unable to replace $path: $!";
}

sub cache_path {
    my ($wos_id, $orcid) = @_;

    my @query_parts;

    push @query_parts, "AI=($wos_id)"
        if $wos_id;

    push @query_parts, "AI=($orcid)"
        if $orcid;

    my $query = join ' OR ', @query_parts;

    my $key =
        "wos_all_v3:$query:$page_size:$max_records:$database";

    return "$cache_dir/" . md5_hex($key) . '.json';
}

sub cache_is_valid {
    my ($path) = @_;

    return 0 unless -f $path;

    my $age = time - (stat($path))[9];

    return 0 if $age > $cache_ttl;

    my $cached = read_json_file($path);

    return 0 unless ref($cached) eq 'HASH';
    return 0 unless ref($cached->{items}) eq 'ARRAY';
    return 0 if $cached->{error};

    return 1;
}

sub value_text {
    my ($value) = @_;

    return '' unless defined $value;

    if (!ref $value) {
        return trim($value);
    }

    if (ref($value) eq 'ARRAY') {
        return join ' ',
            grep { $_ ne '' }
            map  { value_text($_) } @{$value};
    }

    if (ref($value) eq 'HASH') {
        for my $key (
            qw(
                displayName
                display_name
                fullName
                full_name
                standardName
                standard_name
                wosStandard
                name
                value
                text
            )
        ) {
            my $candidate =
                value_text($value->{$key});

            return $candidate
                if $candidate ne '';
        }
    }

    return '';
}

sub author_identifier_matches {
    my ($author, $wos_id, $orcid) = @_;

    return 0 unless ref($author) eq 'HASH';

    my @values;

    for my $key (
        qw(
            researcherId
            researcherID
            rid
            wosResearcherId
            wos_researcher_id
            orcid
            ORCID
            identifier
            identifiers
        )
    ) {
        next unless exists $author->{$key};

        if (ref($author->{$key}) eq 'HASH') {
            push @values,
                values %{ $author->{$key} };
        }
        elsif (ref($author->{$key}) eq 'ARRAY') {
            push @values,
                @{ $author->{$key} };
        }
        else {
            push @values, $author->{$key};
        }
    }

    for my $value (@values) {
        next if ref($value);

        my $text = trim($value);

        return 1
            if $wos_id
            && normalize_identifier($text)
                eq normalize_identifier($wos_id);

        return 1
            if $orcid
            && normalize_orcid($text)
                eq normalize_orcid($orcid);
    }

    return 0;
}

sub extract_matching_author_name {
    my ($document, $wos_id, $orcid) = @_;

    return '' unless ref($document) eq 'HASH';

    my @author_collections;

    for my $key (
        qw(
            authors
            author
            names
            contributors
        )
    ) {
        next unless exists $document->{$key};

        my $collection = $document->{$key};

        if (ref($collection) eq 'ARRAY') {
            push @author_collections, @{$collection};
        }
        elsif (ref($collection) eq 'HASH') {
            if (ref($collection->{authors}) eq 'ARRAY') {
                push @author_collections,
                    @{ $collection->{authors} };
            }
            else {
                push @author_collections, $collection;
            }
        }
    }

    for my $author (@author_collections) {
        next unless ref($author) eq 'HASH';
        next unless author_identifier_matches(
            $author,
            $wos_id,
            $orcid
        );

        my $name = value_text($author);

        return $name if $name ne '';
    }

    return '';
}

sub fetch_wos {
    my ($wos_id, $orcid) = @_;

    die "Web of Science API key missing in $env_file\n"
        unless $api_key;

    my @query_parts;

    push @query_parts, "AI=($wos_id)"
        if $wos_id;

    push @query_parts, "AI=($orcid)"
        if $orcid;

    my $query = join ' OR ', @query_parts;

    my @items;
    my @raw_documents;
    my $published_name = '';

    my $ua = LWP::UserAgent->new(
        agent   => 'BU-Koha-RIMS-WoS-Sync/1.0',
        timeout => 45,
    );

    $ua->env_proxy;

    my $page = 1;

    while (@items < $max_records) {
        my $url =
              'https://api.clarivate.com/apis/wos-starter/v1/documents'
            . '?q='
            . uri_escape_utf8($query)
            . '&db='
            . uri_escape_utf8($database)
            . '&limit='
            . uri_escape_utf8($page_size)
            . '&page='
            . uri_escape_utf8($page);

        my $request =
            HTTP::Request->new(GET => $url);

        $request->header(
            'X-ApiKey' => $api_key
        );

        $request->header(
            'Accept' => 'application/json'
        );

        my $response = $ua->request($request);

        if (!$response->is_success) {
            die "WoS HTTP "
                . $response->code
                . ': '
                . $response->status_line
                . "\n";
        }

        my $json;

        eval {
            $json =
                decode_json($response->decoded_content);
        };

        die "Invalid WoS JSON response\n"
            unless ref($json) eq 'HASH';

        my $hits =
               $json->{hits}
            || $json->{documents}
            || $json->{data}
            || [];

        last unless ref($hits) eq 'ARRAY';
        last unless @{$hits};

        for my $document (@{$hits}) {
            next unless ref($document) eq 'HASH';

            push @raw_documents, $document;

            if (!$published_name) {
                $published_name =
                    extract_matching_author_name(
                        $document,
                        $wos_id,
                        $orcid
                    );
            }

            my $title =
                value_text(
                       $document->{title}
                    || $document->{articleTitle}
                    || $document->{name}
                );

            my $journal = '';

            if (ref($document->{source}) eq 'HASH') {
                $journal =
                    value_text(
                           $document->{source}->{sourceTitle}
                        || $document->{source}->{title}
                    );
            }
            else {
                $journal =
                    value_text(
                           $document->{source}
                        || $document->{journal}
                    );
            }

            my $year = '';

            if (ref($document->{source}) eq 'HASH') {
                $year =
                    value_text(
                        $document->{source}->{publishYear}
                    );
            }

            $year ||= value_text(
                   $document->{year}
                || $document->{publishYear}
                || $document->{publicationDate}
                || $document->{publishedDate}
            );

            $year = $1 if $year =~ /(\d{4})/;

            my $doi = '';

            if (ref($document->{identifiers}) eq 'HASH') {
                $doi =
                    value_text(
                           $document->{identifiers}->{doi}
                        || $document->{identifiers}->{DOI}
                    );
            }

            $doi ||= value_text($document->{doi});

            my $uid =
                value_text(
                       $document->{uid}
                    || $document->{UT}
                    || $document->{id}
                );

            my $citation_count =
                value_text(
                       $document->{timesCited}
                    || $document->{citations}
                );

            $citation_count =
                $citation_count =~ /^\d+$/
                ? int($citation_count)
                : 0;

            my $document_type =
                value_text(
                       $document->{documentType}
                    || $document->{type}
                );

            push @items, {
                title         => $title,
                source        => $journal,
                date          => $year,
                doi           => $doi,
                uid           => $uid,
                cites         => $citation_count,
                document_type => $document_type,
                url           =>
                    $uid
                    ? 'https://www.webofscience.com/wos/woscc/full-record/'
                        . $uid
                    : '',
                raw           => $document,
            };

            last if @items >= $max_records;
        }

        $page++;

        last if scalar(@{$hits}) < $page_size;
        last if $page > 30;
    }

    return {
        items          => \@items,
        error          => '',
        raw_documents  => \@raw_documents,
        published_name => $published_name,
    };
}


sub fetch_researcher_identifiers {
    my ($borrowernumber) = @_;

    my ($wos_id, $orcid);

    # RIMS_WOS_AUTHORITATIVE_PRIMARY_GATE_V1
# Primary source: normalised identifier registry.
    my $rows = $dbh->selectall_arrayref(
        q{
            SELECT
                LOWER(identifier_type) AS identifier_type,
                identifier_value
            FROM researcher_identifiers
            WHERE borrowernumber = ?
              AND is_active = 1
              AND is_primary = 1
              AND verification_status = 'verified'
              AND LOWER(identifier_type) IN (
                  'wos',
                  'web_of_science',
                  'web of science',
                  'wos_researcher_id',
                  'researcherid',
                  'researcher_id',
                  'orcid'
              )
            ORDER BY is_primary DESC, id
        },
        { Slice => {} },
        $borrowernumber
    );

    for my $row (@{$rows}) {
        my $type =
            lc trim($row->{identifier_type});

        my $value =
            trim($row->{identifier_value});

        if (
            !$wos_id
            && $type ne 'orcid'
        ) {
            $wos_id =
                normalize_identifier($value);
        }

        if (
            !$orcid
            && $type eq 'orcid'
        ) {
            $orcid =
                normalize_orcid($value);
        }
    }

    # Compatibility fallback:
    # Older/current Koha researcher profiles may store identifiers
    # directly in custom_profile_details rather than in the registry.
    if (
        (!$wos_id || !$orcid)
        && table_exists('custom_profile_details')
    ) {
        my $wos_column = first_existing_column(
            'custom_profile_details',
            qw(
                wos_researcher_id
                wos_id
                web_of_science_id
                researcher_id
                researcherid
            )
        );

        my $orcid_column = first_existing_column(
            'custom_profile_details',
            qw(
                orcid
                orcid_id
                orcid_identifier
            )
        );

        my @select_parts = ('borrowernumber');

        push @select_parts,
            "$wos_column AS fallback_wos"
            if $wos_column;

        push @select_parts,
            "$orcid_column AS fallback_orcid"
            if $orcid_column;

        if (@select_parts > 1) {
            my $sql =
                  'SELECT '
                . join(', ', @select_parts)
                . ' FROM custom_profile_details'
                . ' WHERE borrowernumber = ?'
                . ' LIMIT 1';

            my $profile =
                $dbh->selectrow_hashref(
                    $sql,
                    undef,
                    $borrowernumber
                );

            if ($profile) {
                # RIMS_WOS_NO_PROFILE_IDENTIFIER_FALLBACK_V1
                # WoS identity must come only from the verified,
                # primary, active identifier registry.  Do not
                # resurrect a stale denormalized profile identifier.

                if (
                    !$orcid
                    && $profile->{fallback_orcid}
                ) {
                    $orcid =
                        normalize_orcid(
                            $profile->{fallback_orcid}
                        );
                }
            }
        }
    }

    return ($wos_id || '', $orcid || '');
}

sub eligible_researchers {
    my $verification_column =
        first_existing_column(
            'custom_profile_details',
            qw(
                verification_status
                profile_verification_status
            )
        );

    my $sync_column =
        first_existing_column(
            'custom_profile_details',
            qw(
                sync_enabled
                api_sync_enabled
            )
        );

    if ($borrower) {
        my $sql =
            q{
                SELECT borrowernumber
                FROM custom_profile_details
                WHERE borrowernumber = ?
            };

        $sql .=
            " AND $verification_column = 'verified'"
            if $verification_column;

        $sql .=
            " AND $sync_column = 1"
            if $sync_column;

        $sql .= ' LIMIT 1';

        return $dbh->selectcol_arrayref(
            $sql,
            undef,
            $borrower
        );
    }

    # Do not join only to researcher_identifiers here.
    # Every verified, sync-enabled profile is evaluated, and the
    # identifier resolver supports both registry and profile storage.
    my $sql =
        q{
            SELECT DISTINCT borrowernumber
            FROM custom_profile_details
            WHERE 1 = 1
        };

    $sql .=
        " AND $verification_column = 'verified'"
        if $verification_column;

    $sql .=
        " AND $sync_column = 1"
        if $sync_column;

    $sql .= ' ORDER BY borrowernumber';

    return $dbh->selectcol_arrayref($sql);
}

sub start_job {

    my ($borrowernumber, $metadata) = @_;

    $dbh->do(
        q{
            INSERT INTO researcher_sync_jobs (
                borrowernumber,
                source_name,
                job_type,
                job_status,
                started_at,
                metadata_json
            )
            VALUES (?, 'wos', 'automatic', 'running', NOW(), ?)
        },
        undef,
        $borrowernumber,
        encode_json($metadata)
    );

    return $dbh->{mysql_insertid};
}

sub finish_job {
    my ($job_id, $stats) = @_;

    $dbh->do(
        q{
            UPDATE researcher_sync_jobs
            SET
                job_status        = 'completed',
                completed_at      = NOW(),
                records_found     = ?,
                records_processed = ?,
                records_added     = ?,
                records_updated   = ?,
                records_linked    = ?,
                error_message     = NULL,
                metadata_json     = ?
            WHERE id = ?
        },
        undef,
        $stats->{found},
        $stats->{processed},
        $stats->{added},
        $stats->{updated},
        $stats->{linked},
        encode_json($stats->{metadata}),
        $job_id
    );
}

sub fail_job {
    my ($job_id, $error) = @_;

    $error = substr($error || 'Unknown error', 0, 4000);

    $dbh->do(
        q{
            UPDATE researcher_sync_jobs
            SET
                job_status    = 'failed',
                completed_at  = NOW(),
                error_message = ?
            WHERE id = ?
        },
        undef,
        $error,
        $job_id
    );
}

sub find_or_create_master {
    my ($item) = @_;

    my $doi =
        normalize_doi($item->{doi});

    my $title =
        trim($item->{title});

    my $normalised_title =
        normalize_title($title);

    my $year =
        $item->{date};

    $year =
        ($year && $year =~ /(\d{4})/)
        ? int($1)
        : undef;

    my $publication_id;

    if ($doi) {
        $publication_id =
            $dbh->selectrow_array(
                q{
                    SELECT id
                    FROM researcher_publications_master
                    WHERE normalised_doi = ?
                    ORDER BY id
                    LIMIT 1
                },
                undef,
                $doi
            );
    }

    if (!$publication_id && $normalised_title) {
        if ($year) {
            $publication_id =
                $dbh->selectrow_array(
                    q{
                        SELECT id
                        FROM researcher_publications_master
                        WHERE normalised_title = ?
                          AND publication_year = ?
                        ORDER BY id
                        LIMIT 1
                    },
                    undef,
                    $normalised_title,
                    $year
                );
        }
        else {
            $publication_id =
                $dbh->selectrow_array(
                    q{
                        SELECT id
                        FROM researcher_publications_master
                        WHERE normalised_title = ?
                        ORDER BY id
                        LIMIT 1
                    },
                    undef,
                    $normalised_title
                );
        }
    }

    if ($publication_id) {
        $dbh->do(
            q{
                UPDATE researcher_publications_master
                SET
                    doi = CASE
                        WHEN (doi IS NULL OR doi = '')
                        THEN ?
                        ELSE doi
                    END,
                    normalised_doi = CASE
                        WHEN (
                            normalised_doi IS NULL
                            OR normalised_doi = ''
                        )
                        THEN ?
                        ELSE normalised_doi
                    END,
                    journal = CASE
                        WHEN (journal IS NULL OR journal = '')
                        THEN ?
                        ELSE journal
                    END,
                    publication_year = COALESCE(
                        publication_year,
                        ?
                    ),
                    document_type = CASE
                        WHEN (
                            document_type IS NULL
                            OR document_type = ''
                        )
                        THEN ?
                        ELSE document_type
                    END,
                    updated_at = NOW()
                WHERE id = ?
            },
            undef,
            ($doi || undef),
            ($doi || undef),
            trim($item->{source}) || undef,
            $year,
            trim($item->{document_type}) || undef,
            $publication_id
        );

        return ($publication_id, 0);
    }

    my $publication_key =
        $doi
        ? "doi:$doi"
        : 'wos:' . (
            normalize_identifier($item->{uid})
            || sha1_hex($normalised_title)
        );

    $dbh->do(
        q{
            INSERT INTO researcher_publications_master (
                publication_key,
                doi,
                normalised_doi,
                title,
                normalised_title,
                journal,
                publication_year,
                document_type,
                created_at,
                updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())
        },
        undef,
        $publication_key,
        ($doi || undef),
        ($doi || undef),
        $title,
        $normalised_title,
        trim($item->{source}) || undef,
        $year,
        trim($item->{document_type}) || undef
    );

    return ($dbh->{mysql_insertid}, 1);
}

sub save_source_record {
    my ($publication_id, $item) = @_;

    my $uid =
        trim($item->{uid});

    return 0 unless $uid;

    my $existing =
        $dbh->selectrow_array(
            q{
                SELECT id
                FROM researcher_publication_sources
                WHERE source_name = 'wos'
                  AND source_record_id = ?
                LIMIT 1
            },
            undef,
            $uid
        );

    if ($existing) {
        $dbh->do(
            q{
                UPDATE researcher_publication_sources
                SET
                    publication_id = ?,
                    source_url     = ?,
                    citation_count = ?,
                    raw_json       = ?,
                    last_synced_at = NOW()
                WHERE id = ?
            },
            undef,
            $publication_id,
            trim($item->{url}) || undef,
            int($item->{cites} || 0),
            encode_json($item->{raw} || {}),
            $existing
        );

        return 0;
    }

    $dbh->do(
        q{
            INSERT INTO researcher_publication_sources (
                publication_id,
                source_name,
                source_record_id,
                source_url,
                citation_count,
                raw_json,
                first_seen_at,
                last_synced_at
            )
            VALUES (?, 'wos', ?, ?, ?, ?, NOW(), NOW())
        },
        undef,
        $publication_id,
        $uid,
        trim($item->{url}) || undef,
        int($item->{cites} || 0),
        encode_json($item->{raw} || {})
    );

    return 1;
}

# RIMS_WOS_SCORE_INTEGRITY_V1
sub save_researcher_link {
    my (
        $borrowernumber,
        $publication_id,
        $wos_id,
        $author_name
    ) = @_;

    my $existing =
        $dbh->selectrow_array(
            q{
                SELECT id
                FROM researcher_publication_links
                WHERE borrowernumber = ?
                  AND publication_id = ?
                  AND source_name = 'wos'
                LIMIT 1
            },
            undef,
            $borrowernumber,
            $publication_id
        );

    if ($existing) {
        $dbh->do(
            q{
                UPDATE researcher_publication_links
                SET
                    source_author_id   = ?,
                    author_name        = CASE
                        WHEN ? <> ''
                        THEN ?
                        ELSE author_name
                    END,
                    affiliation_status = 'institution_affiliation_match',
                    match_score        = CASE
                        WHEN ? <> '' THEN 92.00
                        ELSE 80.00
                    END,
                    system_decision    = 'confirmed',
                    review_status      = 'auto_confirmed',
                    last_confirmed_at  = NOW()
                WHERE id = ?
            },
            undef,
            $wos_id,
            ($author_name || ''),
            ($author_name || ''),
            ($author_name || ''),
            $existing
        );

        return 0;
    }

    $dbh->do(
        q{
            INSERT INTO researcher_publication_links (
                borrowernumber,
                publication_id,
                source_name,
                source_author_id,
                author_name,
                affiliation_status,
                match_score,
                system_decision,
                review_status,
                first_linked_at,
                last_confirmed_at
            )
            VALUES (
                ?,
                ?,
                'wos',
                ?,
                ?,
                'institution_affiliation_match',
                CASE
                    WHEN ? <> '' THEN 92.00
                    ELSE 80.00
                END,
                'confirmed',
                'auto_confirmed',
                NOW(),
                NOW()
            )
        },
        undef,
        $borrowernumber,
        $publication_id,
        $wos_id,
        ($author_name || undef),
        ($author_name || '')
    );

    return 1;
}

sub save_identity_and_variant {
    my (
        $borrowernumber,
        $wos_id,
        $orcid,
        $published_name,
        $raw_documents
    ) = @_;

    $published_name =
        trim($published_name);

    return unless $published_name;

    if (
        table_exists(
            'researcher_author_identity_cache'
        )
    ) {
        $dbh->do(
            q{
                INSERT INTO researcher_author_identity_cache (
                    borrowernumber,
                    source_name,
                    source_author_id,
                    display_name,
                    published_name,
                    profile_url,
                    orcid,
                    raw_json,
                    extraction_method,
                    first_fetched_at,
                    last_fetched_at,
                    updated_at
                )
                VALUES (
                    ?,
                    'wos',
                    ?,
                    ?,
                    ?,
                    ?,
                    ?,
                    ?,
                    'wos-starter-exact-author-identifier',
                    NOW(),
                    NOW(),
                    NOW()
                )
                ON DUPLICATE KEY UPDATE
                    display_name      = VALUES(display_name),
                    published_name    = VALUES(published_name),
                    profile_url       = VALUES(profile_url),
                    orcid             = VALUES(orcid),
                    raw_json          = VALUES(raw_json),
                    extraction_method = VALUES(extraction_method),
                    last_fetched_at   = NOW(),
                    updated_at        = NOW()
            },
            undef,
            $borrowernumber,
            $wos_id,
            $published_name,
            $published_name,
            "https://www.webofscience.com/wos/author/record/$wos_id",
            ($orcid || undef),
            encode_json(
                $raw_documents || []
            )
        );
    }

    if (
        table_exists(
            'researcher_name_variants'
        )
    ) {
        my $normalised =
            normalize_title($published_name);

        $dbh->do(
            q{
                INSERT INTO researcher_name_variants (
                    borrowernumber,
                    name_variant,
                    normalised_variant,
                    source,
                    is_verified,
                    verified_by,
                    verified_at,
                    created_at,
                    updated_at
                )
                VALUES (
                    ?,
                    ?,
                    ?,
                    'wos-api',
                    1,
                    NULL,
                    NOW(),
                    NOW(),
                    NOW()
                )
                ON DUPLICATE KEY UPDATE
                    normalised_variant =
                        VALUES(normalised_variant),
                    source       = 'wos-api',
                    is_verified  = 1,
                    verified_at = NOW(),
                    updated_at   = NOW()
            },
            undef,
            $borrowernumber,
            $published_name,
            $normalised
        );
    }
}

sub add_audit_entry {
    my ($borrowernumber, $reason) = @_;

    return unless table_exists(
        'researcher_audit_log'
    );

    eval {
        $dbh->do(
            q{
                INSERT INTO researcher_audit_log (
                    borrowernumber,
                    action_type,
                    action_source,
                    reason,
                    created_at
                )
                VALUES (
                    ?,
                    'wos_publications_synced',
                    'sync',
                    ?,
                    NOW()
                )
            },
            undef,
            $borrowernumber,
            $reason
        );
    };
}

sub process_researcher {
    my ($borrowernumber) = @_;

    my ($wos_id, $orcid) =
        fetch_researcher_identifiers(
            $borrowernumber
        );

    if (!$wos_id) {
        log_message(
            "Borrower $borrowernumber skipped: "
            . 'no verified active WoS identifier'
        );

        return;
    }

    my $lock_file =
        "$lock_dir/rims-wos-sync-$borrowernumber.lock";

    open my $lock_fh, '>', $lock_file
        or die "Unable to open lock $lock_file: $!";

    return unless flock(
        $lock_fh,
        2 | 4
    );

    my $job_id = start_job(
        $borrowernumber,
        {
            wos_researcher_id => $wos_id,
            orcid             => $orcid,
            mode              => 'cache-first',
        }
    );

    eval {
        my $path =
            cache_path($wos_id, $orcid);

        my $payload;

        if (!$force_api && cache_is_valid($path)) {
            $payload = read_json_file($path);

            log_message(
                "Borrower $borrowernumber: "
                . "using WoS cache $path"
            );
        }
        else {
            log_message(
                "Borrower $borrowernumber: "
                . 'fetching WoS API'
            );

            $payload =
                fetch_wos($wos_id, $orcid);

            write_json_file(
                $path,
                {
                    items          =>
                        $payload->{items} || [],
                    error          =>
                        $payload->{error} || '',
                    published_name =>
                        $payload->{published_name}
                        || '',
                    raw_documents  =>
                        $payload->{raw_documents}
                        || [],
                }
            );
        }

        die(
            $payload->{error}
            || 'WoS synchronization returned an error'
        ) if $payload->{error};

        my $items =
            $payload->{items} || [];

        die "WoS response does not contain items\n"
            unless ref($items) eq 'ARRAY';

        my $published_name =
            trim(
                $payload->{published_name}
                || ''
            );

        if (!$published_name) {
            for my $item (@{$items}) {
                next unless ref($item) eq 'HASH';

                my $name =
                    extract_matching_author_name(
                        $item->{raw} || {},
                        $wos_id,
                        $orcid
                    );

                if ($name) {
                    $published_name = $name;
                    last;
                }
            }
        }

        my %stats = (
            found     => scalar(@{$items}),
            processed => 0,
            added     => 0,
            updated   => 0,
            linked    => 0,
            metadata  => {
                wos_researcher_id =>
                    $wos_id,
                orcid =>
                    $orcid,
                cache_file =>
                    $path,
                match_method =>
                    'doi-first-title-year-fallback',
            },
        );

        $dbh->begin_work;

        for my $item (@{$items}) {
            next unless ref($item) eq 'HASH';
            next unless trim($item->{title});

            my (
                $publication_id,
                $was_added
            ) = find_or_create_master($item);

            $stats{added} += $was_added;
            $stats{updated}++
                unless $was_added;

            save_source_record(
                $publication_id,
                $item
            );

            $stats{linked} +=
                save_researcher_link(
                    $borrowernumber,
                    $publication_id,
                    $wos_id,
                    $published_name
                );

            $stats{processed}++;
        }

        save_identity_and_variant(
            $borrowernumber,
            $wos_id,
            $orcid,
            $published_name,
            $payload->{raw_documents}
                || [
                    map {
                        $_->{raw} || {}
                    } @{$items}
                ]
        );

        add_audit_entry(
            $borrowernumber,
            'Web of Science automatic synchronization '
            . 'completed from protected cache/API workflow'
        );

        finish_job(
            $job_id,
            \%stats
        );

        $dbh->commit;

        log_message(
            "Borrower $borrowernumber completed: "
            . "found=$stats{found}, "
            . "processed=$stats{processed}, "
            . "new_master=$stats{added}, "
            . "linked=$stats{linked}"
        );

        1;
    } or do {
        my $error =
            $@ || 'Unknown synchronization error';

        eval {
            $dbh->rollback;
        };

        eval {
            fail_job($job_id, $error);
        };

        log_message(
            "Borrower $borrowernumber FAILED: $error"
        );
    };

    close $lock_fh;
}

my $researchers =
    eligible_researchers();

for my $researcher (@{$researchers}) {
    process_researcher($researcher);
}

exit 0;
