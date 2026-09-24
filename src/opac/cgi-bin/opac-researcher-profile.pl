#!/usr/bin/perl

use Modern::Perl;
use CGI qw(-utf8);
use C4::Auth qw(get_template_and_user);
use C4::Output qw(output_html_with_http_headers);
use C4::Context;
use LWP::UserAgent;
use HTTP::Request;
use JSON qw(decode_json encode_json);
use URI::Escape qw(uri_escape_utf8);
use Digest::MD5 qw(md5_hex);
use File::Path qw(make_path);

my $query = CGI->new;

my ( $template, $loggedinuser, $cookie ) = get_template_and_user({
    template_name   => "opac-researcher-profile.tt",
    query           => $query,
    type            => "opac",
    authnotrequired => 1,
});

my $dbh = C4::Context->dbh;
my $userenv = C4::Context->userenv || {};
my $viewer_borrowernumber = $userenv->{number} || $loggedinuser || 0;

my $requested_id  = $query->param('id')  || '';
my $requested_url = $query->param('url') || '';

$requested_url =~ s/^\s+|\s+$//g;
$requested_url =~ s/[^A-Za-z0-9._-]//g;

my $borrowernumber = $requested_id;

if ( !$requested_id && $requested_url ) {
    my $url_bn = $dbh->selectrow_array(
        "SELECT borrowernumber FROM custom_profile_details WHERE custom_url = ? LIMIT 1",
        undef,
        $requested_url
    );
    $borrowernumber = $url_bn if $url_bn;
}

if ( !$borrowernumber && $viewer_borrowernumber && $viewer_borrowernumber =~ /^\d+$/ ) {
    $borrowernumber = $viewer_borrowernumber;
}

my $error = '';
my $profile = {};
my $borrower = {};
my $has_profile = 0;
my $has_photo = 0;
my $can_edit = 0;

# BEGIN PERMANENT RESEARCHER IDENTITY V2
#
# A Koha borrower account is an employment/account instance.
# researcher_uuid is the permanent scholarly identity.
#
my $researcher_uuid = '';
my @identity_borrowernumbers;
# END PERMANENT RESEARCHER IDENTITY V2

sub detect_instance {
    if ($ENV{KOHA_CONF} && $ENV{KOHA_CONF} =~ m{/etc/koha/sites/([^/]+)/koha-conf\.xml}) {
        return $1;
    }
    return $ENV{KOHA_INSTANCE} || 'INSTANCE';
}

my $instance = detect_instance();

sub read_env_file {
    my ($file) = @_;
    my %env;
    return %env unless -f $file;

    open my $fh, '<', $file or return %env;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /^\s*#/;
        if ($line =~ /^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/) {
            my ($key, $value) = ($1, $2);

            $value =~ s/^"(.*)"$/$1/;
            $value =~ s/^'(.*)'$/$1/;

            $env{$key} = $value;
        }
    }
    close $fh;
    return %env;
}

my $env_file = "/etc/koha/sites/$instance/research-api.env";
my %api_env = read_env_file($env_file);

# API credentials must be loaded only from the protected environment file.
$api_env{SCOPUS_API_KEY} ||= q{};
$api_env{SCOPUS_AFFILIATION_ID} ||= '';
$api_env{WOS_API_KEY} ||= q{};
$api_env{WOS_DB} ||= 'WOS';
$api_env{RECENT_LIMIT} ||= '300';
$api_env{SCOPUS_MAX_RECORDS} ||= '300';
$api_env{WOS_MAX_RECORDS} ||= '300';
$api_env{SCOPUS_PAGE_SIZE} ||= '25';
$api_env{WOS_PAGE_SIZE} ||= '50';
$api_env{CACHE_TTL_SECONDS} ||= '3600';
$api_env{WOS_CACHE_TTL_SECONDS} ||= '86400';
$api_env{WOS_RATE_LIMIT_TTL_SECONDS} ||= '21600';


my $cache_dir = "/var/cache/koha/$instance/research-publications";
make_path($cache_dir) unless -d $cache_dir;

sub safe_url {
    my ($url) = @_;
    $url ||= '';
    $url =~ s/^\s+|\s+$//g;
    return '' unless $url =~ m{^https?://}i;
    return $url;
}

sub clean_id {
    my ($v) = @_;
    $v ||= '';
    $v =~ s/^\s+|\s+$//g;
    $v =~ s/[^A-Za-z0-9\-]//g;
    return $v;
}

sub norm_text_value {
    my ($v) = @_;

    return '' unless defined $v;

    if (ref($v) eq 'ARRAY') {
        return '' unless @$v;
        return norm_text_value($v->[0]);
    }

    if (ref($v) eq 'HASH') {
        for my $k (qw(count value total timesCited citations all localCount displayName title sourceTitle year uid id doi DOI)) {
            return norm_text_value($v->{$k}) if exists $v->{$k};
        }
        for my $val (values %$v) {
            my $out = norm_text_value($val);
            return $out if defined $out && $out ne '';
        }
        return '';
    }

    $v = "$v";
    $v =~ s/^\s+|\s+$//g;
    return $v;
}

sub norm_count_value {
    my ($v) = @_;
    my $out = norm_text_value($v);
    return '' unless defined $out && $out ne '';
    return $1 if $out =~ /(\d+)/;
    return '';
}

sub cache_get {
    my ($key, $ttl) = @_;
    my $file = "$cache_dir/" . md5_hex($key) . ".json";
    return undef unless -f $file;
    return undef if time - (stat($file))[9] > $ttl;

    open my $fh, '<', $file or return undef;
    local $/;
    my $txt = <$fh>;
    close $fh;

    my $data;
    eval { $data = decode_json($txt); };
    return $data;
}

sub cache_set {
    my ($key, $data) = @_;
    my $file = "$cache_dir/" . md5_hex($key) . ".json";
    open my $fh, '>', $file or return;
    print $fh encode_json($data);
    close $fh;
}

sub fetch_json {
    my ($url, $headers) = @_;

    my $ua = LWP::UserAgent->new(
        timeout => 30,
        agent   => 'Koha-BU-Research-Profile/2.0'
    );

    my $req = HTTP::Request->new(GET => $url);
    $req->header('Accept' => 'application/json');

    for my $h (keys %{ $headers || {} }) {
        $req->header($h => $headers->{$h});
    }

    my $res = $ua->request($req);

    if (!$res->is_success) {
        return (undef, $res->status_line);
    }

    my $json;
    eval { $json = decode_json($res->decoded_content); };
    if ($@) {
        return (undef, "JSON parse error");
    }

    return ($json, '');
}

sub scopus_web_url {
    my ($e) = @_;
    my $scp = '';

    if ($e->{'dc:identifier'} && $e->{'dc:identifier'} =~ /SCOPUS_ID:(\d+)/) {
        $scp = $1;
    } elsif ($e->{'prism:url'} && $e->{'prism:url'} =~ m{/scopus_id/(\d+)}) {
        $scp = $1;
    } elsif ($e->{'eid'} && $e->{'eid'} =~ /2-s2\.0-(\d+)/) {
        $scp = $1;
    }

    return "https://www.scopus.com/inward/record.uri?partnerID=HzOxMe3b&scp=$scp&origin=inward" if $scp;

    return '';
}

sub wos_full_record_url {
    my ($uid) = @_;
    $uid = norm_text_value($uid);
    return '' unless $uid;

    $uid =~ s/^\s+|\s+$//g;
    $uid = "WOS:$uid" if $uid =~ /^\d/;

    return "https://www.webofscience.com/wos/woscc/full-record/$uid";
}

sub fetch_scopus_publications {
    my ($scopus_id) = @_;
    $scopus_id = clean_id($scopus_id);
    return ([], '') unless $scopus_id;

    my $api_key = $api_env{SCOPUS_API_KEY} || '';
    return ([], 'Scopus API key missing') unless $api_key;

    my $page_size = $api_env{SCOPUS_PAGE_SIZE} || 25;
    my $max       = $api_env{SCOPUS_MAX_RECORDS} || $api_env{RECENT_LIMIT} || 300;
    my $ttl       = $api_env{CACHE_TTL_SECONDS} || 3600;

    $page_size = 25 if $page_size > 25;
    $page_size = 25 if $page_size < 1;
    $max       = 300 if $max < 1;

    my $cache_key = "scopus_all_v2:$scopus_id:$page_size:$max";
    if (my $cached = cache_get($cache_key, $ttl)) {
        return ($cached->{items} || [], $cached->{error} || '');
    }

    my @items;
    my $err = '';
    my $q = "AU-ID($scopus_id)";
    my $start = 0;
    my $total = undef;

    while (@items < $max) {
        my $url = "https://api.elsevier.com/content/search/scopus"
                . "?query=" . uri_escape_utf8($q)
                . "&count=" . uri_escape_utf8($page_size)
                . "&start=" . uri_escape_utf8($start)
                . "&sort=-coverDate"
                . "&view=STANDARD"
                . "&httpAccept=application/json";

        my ($json, $this_err) = fetch_json($url, {
            'X-ELS-APIKey' => $api_key,
        });

        if ($this_err) {
            $err = $this_err;
            last;
        }

        my $sr = $json->{'search-results'} || {};
        my $entries = $sr->{'entry'} || [];
        $total = $sr->{'opensearch:totalResults'} if !defined $total;

        last unless ref($entries) eq 'ARRAY' && @$entries;

        for my $e (@$entries) {
            next if $e->{error};

            my $doi = norm_text_value($e->{'prism:doi'});

            push @items, {
                title   => norm_text_value($e->{'dc:title'}),
                source  => norm_text_value($e->{'prism:publicationName'}),
                date    => norm_text_value($e->{'prism:coverDate'}),
                doi     => $doi,
                eid     => norm_text_value($e->{'eid'}),
                cites   => norm_count_value($e->{'citedby-count'}),
                subtype => norm_text_value($e->{'subtypeDescription'}),
                url     => scopus_web_url($e),
            };

            last if @items >= $max;
        }

        $start += $page_size;

        last if defined $total && $start >= $total;
        last if $start > 1000;
    }

    cache_set($cache_key, { items => \@items, error => $err });
    return (\@items, $err);
}

sub fetch_wos_publications {
    my ($researcher_id, $orcid) = @_;

    $researcher_id = clean_id($researcher_id);
    $orcid = clean_id($orcid);

    return ([], '') unless $researcher_id || $orcid;

    my $api_key = $api_env{WOS_API_KEY} || '';
    return ([], 'Web of Science API key missing') unless $api_key;

    my $db        = $api_env{WOS_DB} || 'WOS';
    my $page_size = $api_env{WOS_PAGE_SIZE} || 50;
    my $max       = $api_env{WOS_MAX_RECORDS} || $api_env{RECENT_LIMIT} || 300;
    my $ttl       = $api_env{WOS_CACHE_TTL_SECONDS}
                    || $api_env{CACHE_TTL_SECONDS}
                    || 86400;

    my $rate_limit_ttl = $api_env{WOS_RATE_LIMIT_TTL_SECONDS}
                         || 21600;

    $page_size = 50 if $page_size > 50;
    $page_size = 50 if $page_size < 1;
    $max       = 300 if $max < 1;

    my $q = '';

    if ($researcher_id) {
        $q = "AI=($researcher_id)";
    }
    elsif ($orcid) {
        $q = "AI=($orcid)";
    }

    my $cache_key = "wos_all_v3:$q:$page_size:$max:$db";
    my $rate_limit_key = "wos_rate_limit_guard";

    if (my $cached = cache_get($cache_key, $ttl)) {
        return ($cached->{items} || [], $cached->{error} || '');
    }

    if (my $guard = cache_get($rate_limit_key, $rate_limit_ttl)) {
        return (
            [],
            $guard->{error}
            || 'Web of Science API rate limit is currently active. Please try again after the next scheduled refresh.'
        );
    }

    my @items;
    my $err = '';
    my $page = 1;

    while (@items < $max) {
        my $url = "https://api.clarivate.com/apis/wos-starter/v1/documents"
                . "?q=" . uri_escape_utf8($q)
                . "&db=" . uri_escape_utf8($db)
                . "&limit=" . uri_escape_utf8($page_size)
                . "&page=" . uri_escape_utf8($page);

        my ($json, $this_err) = fetch_json($url, {
            'X-ApiKey' => $api_key,
        });

        if ($this_err) {
            if ($this_err =~ /^429\b/i
                || $this_err =~ /rate[ -]?limit/i
                || $this_err =~ /too many requests/i) {

                $err = 'Web of Science API rate limit exceeded. '
                     . 'The profile will retry after the protected refresh interval.';

                cache_set(
                    $rate_limit_key,
                    {
                        error      => $err,
                        detectedAt => time,
                    }
                );
            }
            else {
                $err = "Web of Science API error: $this_err";
            }

            last;
        }

        my $hits = $json->{hits} || $json->{documents} || $json->{data} || [];
        last unless ref($hits) eq 'ARRAY' && @$hits;

        my $metadata = ref($json->{metadata}) eq 'HASH'
                       ? $json->{metadata}
                       : {};

        my $total = $metadata->{total}
                    || $metadata->{totalResults}
                    || $metadata->{recordsFound};

        for my $h (@$hits) {
            my $title = '';
            if (ref($h->{title}) eq 'ARRAY') {
                $title = join(' ', map { norm_text_value($_) } @{ $h->{title} });
            } else {
                $title = norm_text_value($h->{title} || $h->{articleTitle} || $h->{name});
            }

            my $source = '';
            if (ref($h->{source}) eq 'HASH') {
                $source = norm_text_value($h->{source}->{sourceTitle} || $h->{source}->{title});
            } else {
                $source = norm_text_value($h->{source} || $h->{journal});
            }

            my $date = norm_text_value(
                (ref($h->{source}) eq 'HASH' ? $h->{source}->{publishYear} : '')
                || $h->{year}
                || $h->{publishedDate}
                || $h->{publicationDate}
            );

            my $doi = '';
            if (ref($h->{identifiers}) eq 'HASH') {
                $doi = norm_text_value($h->{identifiers}->{doi} || $h->{identifiers}->{DOI});
            } else {
                $doi = norm_text_value($h->{doi});
            }

            my $uid = norm_text_value($h->{uid} || $h->{UT} || $h->{id});

            push @items, {
                title  => $title,
                source => $source,
                date   => $date,
                doi    => $doi,
                uid    => $uid,
                cites  => norm_count_value($h->{timesCited} || $h->{citations}),
                url    => wos_full_record_url($uid),
            };

            last if @items >= $max;
        }

        last if defined $total && $total =~ /^\d+$/ && @items >= $total;
        last if @$hits < $page_size;

        $page++;
        last if $page > 30;
    }

    cache_set($cache_key, { items => \@items, error => $err });
    return (\@items, $err);
}

if ( !$borrowernumber || $borrowernumber !~ /^\d+$/ ) {
    $error = "Please select a researcher to open the research profile.";
} else {
    $profile = $dbh->selectrow_hashref(
        "SELECT * FROM custom_profile_details WHERE borrowernumber = (
                    SELECT COALESCE(
                        (
                            SELECT cpd_direct.borrowernumber
                            FROM custom_profile_details cpd_direct
                            WHERE cpd_direct.borrowernumber = ?
                            LIMIT 1
                        ),
                        (
                            SELECT cpd_uuid.borrowernumber
                            FROM researcher_patron_links requested_link

                            JOIN custom_profile_details cpd_uuid
                              ON cpd_uuid.researcher_uuid =
                                 requested_link.researcher_uuid

                            WHERE requested_link.borrowernumber = ?
                            LIMIT 1
                        )
                    )
                )",
        undef,
        $borrowernumber, $borrowernumber
    ) || {};

    $borrower = $dbh->selectrow_hashref(
        "SELECT borrowernumber, cardnumber, firstname, surname FROM borrowers WHERE borrowernumber = ?",
        undef,
        $borrowernumber
    ) || {};

    $has_profile = $profile->{borrowernumber} ? 1 : 0;

    # BEGIN PERMANENT PROFILE RESOLVER V2
    #
    # requested_borrowernumber:
    #   Koha account used in the incoming URL.
    #
    # canonical_profile_borrowernumber:
    #   historical/current custom_profile_details anchor carrying
    #   the permanent scholarly profile.
    #
    if ($has_profile) {

        $profile->{requested_borrowernumber} =
            $borrowernumber;

        $profile->{canonical_profile_borrowernumber} =
            $profile->{borrowernumber};

        $profile->{profile_resolved_via_identity} =
            (
                defined($borrowernumber)
                &&
                defined($profile->{borrowernumber})
                &&
                "$borrowernumber" ne "$profile->{borrowernumber}"
            ) ? 1 : 0;
    }
    # END PERMANENT PROFILE RESOLVER V2

    # BEGIN PERMANENT UUID RESOLUTION V2
    #
    # First resolve the requested borrower to its permanent researcher.
    # Then collect every historical/current borrower account belonging
    # to that researcher.
    #
    if ($has_profile) {

        $researcher_uuid =
            $profile->{researcher_uuid}
            || '';

        if (!$researcher_uuid) {
            $researcher_uuid =
                $dbh->selectrow_array(
                    q{
                        SELECT researcher_uuid
                        FROM researcher_patron_links
                        WHERE borrowernumber = ?
                        LIMIT 1
                    },
                    undef,
                    $borrowernumber
                ) || '';
        }

        if ($researcher_uuid) {

            my $identity_rows =
                $dbh->selectall_arrayref(
                    q{
                        SELECT borrowernumber
                        FROM researcher_patron_links
                        WHERE researcher_uuid = ?
                        ORDER BY
                            CASE
                                WHEN link_status = 'current'
                                THEN 0
                                ELSE 1
                            END,
                            id
                    },
                    { Slice => {} },
                    $researcher_uuid
                ) || [];

            @identity_borrowernumbers =
                map {
                    $_->{borrowernumber}
                }
                grep {
                    defined $_->{borrowernumber}
                    && $_->{borrowernumber} =~ /^\d+$/
                }
                @{$identity_rows};
        }

        # Compatibility fallback for profiles created before V2.
        if (!@identity_borrowernumbers) {
            @identity_borrowernumbers =
                ($borrowernumber);
        }

        $profile->{researcher_uuid} =
            $researcher_uuid;

        $profile->{identity_account_count} =
            scalar @identity_borrowernumbers;
    }
    # END PERMANENT UUID RESOLUTION V2

    $can_edit = (
        $viewer_borrowernumber
        && $viewer_borrowernumber =~ /^\d+$/
        && $viewer_borrowernumber == $borrowernumber
    ) ? 1 : 0;

    my $table_exists = $dbh->selectrow_array("SHOW TABLES LIKE 'patronimage'");
    if ($table_exists) {
        $has_photo = $dbh->selectrow_array(
            "SELECT COUNT(*) FROM patronimage WHERE borrowernumber = ?",
            undef,
            $borrowernumber
        ) || 0;
    }

    $profile->{website_url} = safe_url($profile->{website});

    $profile->{verification_status} ||= 'pending';
    $profile->{employment_status}   ||= 'active';

    my %verification_labels = (
        pending  => 'Pending Verification',
        verified => 'Verified',
        rejected => 'Rejected',
    );

    my %employment_labels = (
        active    => 'Current Researcher',
        former    => 'Former Researcher',
        external  => 'External Researcher',
        suspended => 'Suspended',
        inactive  => 'Inactive',
    );

    $profile->{verification_label}
        = $verification_labels{
            lc($profile->{verification_status} || '')
          }
        || $profile->{verification_status};

    $profile->{employment_label}
        = $employment_labels{
            lc($profile->{employment_status} || '')
          }
        || $profile->{employment_status};

    $profile->{is_verified}
        = lc($profile->{verification_status} || '') eq 'verified'
        ? 1 : 0;

    $profile->{is_current}
        = lc($profile->{employment_status} || '') eq 'active'
        ? 1 : 0;

    $profile->{is_former}
        = lc($profile->{employment_status} || '') eq 'former'
        ? 1 : 0;
}


my $crossref_verified_pubs = [];
my $crossref_verified_count = 0;
my $crossref_last_synced = '';

if (
    $has_profile
    && $borrowernumber
    && $borrowernumber =~ /^\d+$/
) {
    $crossref_verified_pubs =
        $dbh->selectall_arrayref(
            q{
                SELECT
                    rpm.id AS publication_id,
                    rpm.title,
                    rpm.journal AS source,
                    rpm.publication_year,
                    rpm.document_type,
                    rpm.doi,
                    rps.source_url AS crossref_url,
                    rps.citation_count,
                    rps.last_synced_at
                FROM researcher_publication_links rpl
                INNER JOIN researcher_publications_master rpm
                    ON rpm.id = rpl.publication_id
                INNER JOIN researcher_publication_sources rps
                    ON rps.publication_id = rpm.id
                   AND rps.source_name = 'crossref'
                WHERE rpl.borrowernumber IN (
                    SELECT borrowernumber
                    FROM researcher_patron_links
                    WHERE researcher_uuid = ?
                )
                GROUP BY
                    rpm.id,
                    rpm.title,
                    rpm.journal,
                    rpm.publication_year,
                    rpm.document_type,
                    rpm.doi,
                    rps.source_url,
                    rps.citation_count,
                    rps.last_synced_at
                ORDER BY
                    rpm.publication_year DESC,
                    rpm.id DESC
            },
            { Slice => {} },
            $researcher_uuid
        ) || [];

    for my $publication (
        @{$crossref_verified_pubs}
    ) {
        my $doi = $publication->{doi} || '';

        $doi =~ s/^\s+|\s+$//g;
        $doi =~ s{^https?://(?:dx\.)?doi\.org/}{}i;
        $doi =~ s/^doi:\s*//i;

        $publication->{doi} = $doi;
        $publication->{doi_url} =
            $doi
            ? "https://doi.org/$doi"
            : '';

        $publication->{crossref_url} =
            safe_url(
                $publication->{crossref_url}
            );

        $publication->{display_year} =
            $publication->{publication_year}
            || '';

        $publication->{crossref_verified} = 1;
    }

    $crossref_verified_count =
        scalar @{$crossref_verified_pubs};

    if ($crossref_verified_count) {
        ($crossref_last_synced) =
            $dbh->selectrow_array(
                q{
                    SELECT
                        DATE_FORMAT(
                            MAX(rps.last_synced_at),
                            '%d %M %Y, %h:%i %p'
                        )
                    FROM researcher_publication_links rpl
                    INNER JOIN researcher_publication_sources rps
                        ON rps.publication_id =
                           rpl.publication_id
                       AND rps.source_name =
                           'crossref'
                    WHERE rpl.borrowernumber IN (
                        SELECT borrowernumber
                        FROM researcher_patron_links
                        WHERE researcher_uuid = ?
                    )
                },
                undef,
                $researcher_uuid
            );
    }
}

my ($scopus_pubs, $scopus_error) = ([], '');
my ($wos_pubs, $wos_error) = ([], '');

if ($has_profile) {
    ($scopus_pubs, $scopus_error) = fetch_scopus_publications($profile->{scopus_author_id});
    ($wos_pubs, $wos_error) = fetch_wos_publications($profile->{researcher_id}, $profile->{orcid});
}

$template->param(
    profile       => $profile,
    borrower      => $borrower,
    error         => $error,
    has_profile   => $has_profile,
    has_photo     => $has_photo,
    can_edit      => $can_edit,

    researcher_uuid =>
        $researcher_uuid,

    identity_account_count =>
        scalar(@identity_borrowernumbers),

    now           => time,
    crossref_verified_pubs  =>
        $crossref_verified_pubs,
    crossref_verified_count =>
        $crossref_verified_count,
    crossref_last_synced    =>
        $crossref_last_synced,
    scopus_pubs   => $scopus_pubs,
    scopus_count  => scalar(@$scopus_pubs),
    scopus_error  => $scopus_error,
    wos_pubs      => $wos_pubs,
    wos_count     => scalar(@$wos_pubs),
    wos_error     => $wos_error,
);


# BEGIN OPAC UNIFIED RESEARCH INTELLIGENCE

my $unified_publications = [];
my $unified_summary = {
    total_publications    => 0,
    scopus_publications   => 0,
    wos_publications      => 0,
    crossref_publications => 0,
    total_citations       => 0,
    latest_year           => '',
    last_synced           => '',
};

if (
    $has_profile
    && $borrowernumber
    && $borrowernumber =~ /^\d+$/
) {
    $unified_publications =
        $dbh->selectall_arrayref(
            q{
                SELECT
                    rpm.id AS publication_id,
                    rpm.title,
                    rpm.journal,
                    rpm.publication_date,
                    rpm.publication_year,
                    rpm.document_type,
                    rpm.doi,

                    MAX(
                        CASE
                            WHEN rpl.author_position IS NOT NULL
                            THEN rpl.author_position
                        END
                    ) AS author_position,

                    MAX(
                        CASE
                            WHEN rpl.source_name = 'scopus'
                            THEN rpl.author_name
                        END
                    ) AS scopus_author_name,

                    MAX(
                        CASE
                            WHEN rpl.source_name = 'wos'
                            THEN rpl.author_name
                        END
                    ) AS wos_author_name,

                    MAX(
                        CASE
                            WHEN rpl.source_name = 'crossref'
                            THEN rpl.author_name
                        END
                    ) AS crossref_author_name,

                    MAX(
                        CASE
                            WHEN rpl.author_name IS NOT NULL
                            THEN rpl.author_name
                        END
                    ) AS matched_author_name,

                    MAX(
                        CASE
                            WHEN rps.source_name = 'scopus'
                            THEN 1 ELSE 0
                        END
                    ) AS has_scopus,

                    MAX(
                        CASE
                            WHEN rps.source_name = 'wos'
                            THEN 1 ELSE 0
                        END
                    ) AS has_wos,

                    MAX(
                        CASE
                            WHEN rps.source_name = 'crossref'
                            THEN 1 ELSE 0
                        END
                    ) AS has_crossref,

                    MAX(
                        CASE
                            WHEN rps.source_name = 'scopus'
                            THEN rps.citation_count
                        END
                    ) AS scopus_citations,

                    MAX(
                        CASE
                            WHEN rps.source_name = 'wos'
                            THEN rps.citation_count
                        END
                    ) AS wos_citations,

                    MAX(
                        CASE
                            WHEN rps.source_name = 'crossref'
                            THEN rps.citation_count
                        END
                    ) AS crossref_citations,

                    MAX(
                        CASE
                            WHEN rps.source_name = 'scopus'
                            THEN rps.source_url
                        END
                    ) AS scopus_url,

                    MAX(
                        CASE
                            WHEN rps.source_name = 'wos'
                            THEN rps.source_url
                        END
                    ) AS wos_url,

                    MAX(
                        CASE
                            WHEN rps.source_name = 'crossref'
                            THEN rps.source_url
                        END
                    ) AS crossref_url,

                    MAX(rps.last_synced_at) AS last_synced_at

                FROM researcher_publications_master rpm

                INNER JOIN researcher_publication_links rpl
                    ON rpl.publication_id = rpm.id
                   AND rpl.borrowernumber IN (
                        SELECT borrowernumber
                        FROM researcher_patron_links
                        WHERE researcher_uuid = ?
                   )
                   AND rpl.system_decision = 'confirmed'
                   AND rpl.review_status IN (
                        'confirmed',
                        'auto_confirmed'
                   )

                /* RIMS_CONFIRMED_SOURCE_VISIBILITY_V1
                 *
                 * Overall publication visibility:
                 *   at least one confirmed researcher-publication link.
                 *
                 * Per-source visibility:
                 *   expose provenance only when the same researcher has
                 *   a confirmed link for that exact source.
                 */
                LEFT JOIN researcher_publication_sources rps
                    ON rps.publication_id = rpm.id
                   /* RIMS_CROSSREF_PROVENANCE_VISIBILITY_V2
                    *
                    * Scopus/WoS:
                    *   require a confirmed researcher-source link.
                    *
                    * Crossref:
                    *   Crossref is publication-level enrichment/provenance
                    *   and does not require a dedicated author link.
                    *   The publication itself is already restricted above
                    *   to a confirmed researcher-publication relationship.
                    */
                   AND (
                        rps.source_name = 'crossref'

                        OR EXISTS (
                            SELECT 1
                            FROM researcher_publication_links rpl_source
                            WHERE rpl_source.publication_id =
                                      rpm.id
                              AND rpl_source.borrowernumber IN (
                                    SELECT borrowernumber
                                    FROM researcher_patron_links
                                    WHERE researcher_uuid = ?
                              )
                              AND rpl_source.source_name =
                                      rps.source_name
                              AND rpl_source.source_name IN (
                                    'scopus',
                                    'wos'
                              )
                              AND rpl_source.system_decision =
                                      'confirmed'
                              AND rpl_source.review_status IN (
                                    'confirmed',
                                    'auto_confirmed'
                              )
                        )
                   )

                GROUP BY
                    rpm.id,
                    rpm.title,
                    rpm.journal,
                    rpm.publication_date,
                    rpm.publication_year,
                    rpm.document_type,
                    rpm.doi

                ORDER BY
                    COALESCE(
                        rpm.publication_date,
                        CONCAT(
                            COALESCE(rpm.publication_year, 0),
                            '-01-01'
                        )
                    ) DESC,
                    rpm.id DESC
            },
            { Slice => {} },
            $researcher_uuid,
            $researcher_uuid
        ) || [];

    my $total_citations = 0;
    my $scopus_count = 0;
    my $wos_count = 0;
    my $crossref_count = 0;
    my $latest_year = '';
    my $last_synced = '';

    # BEGIN AUTHOR IDENTITY CACHE FALLBACK V10
    #
    # Author names are fetched from the external API only by the dedicated
    # identity-cache sync. OPAC rendering reads the permanent database cache.
    #
    my $author_identity_cache = {};

    my $identity_cache_table_exists = $dbh->selectrow_array(
        q{
            SELECT COUNT(*)
            FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'researcher_author_identity_cache'
        }
    );

    if ($identity_cache_table_exists) {
        my $identity_rows = $dbh->selectall_arrayref(
            q{
                SELECT
                    source_name,
                    COALESCE(
                        NULLIF(TRIM(published_name), ''),
                        NULLIF(TRIM(display_name), '')
                    ) AS source_published_name,
                    profile_url
                FROM researcher_author_identity_cache
                WHERE borrowernumber = ?
                  AND source_name IN ('scopus', 'wos')
            },
            { Slice => {} },
            $borrowernumber
        ) || [];

        for my $identity (@{$identity_rows}) {
            my $source = lc($identity->{source_name} || '');

            next unless $source eq 'scopus' || $source eq 'wos';

            $author_identity_cache->{$source} = {
                published_name =>
                    $identity->{source_published_name} || '',
                profile_url =>
                    $identity->{profile_url} || '',
            };
        }
    }

    # BEGIN ALL API AUTHOR NAME VARIANTS V11
    my @source_name_groups;

    my $source_name_variant_table_exists =
        $dbh->selectrow_array(
            q{
                SELECT COUNT(*)
                FROM information_schema.TABLES
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME =
                      'researcher_source_name_variants'
            }
        );

    if ($source_name_variant_table_exists) {
        my $source_name_rows =
            $dbh->selectall_arrayref(
                q{
                    SELECT
                        source_name,
                        source_author_id,
                        name_type,
                        name_value,
                        api_json_path,
                        extraction_method,
                        is_primary,
                        profile_url
                    FROM researcher_source_name_variants
                    WHERE borrowernumber = ?
                      AND source_name IN ('scopus', 'wos')
                    ORDER BY
                        FIELD(source_name, 'scopus', 'wos'),
                        is_primary DESC,
                        id ASC
                },
                { Slice => {} },
                $borrowernumber
            ) || [];

        my %groups;

        for my $row (@{$source_name_rows}) {
            my $source =
                lc($row->{source_name} || '');

            next
                unless $source eq 'scopus'
                || $source eq 'wos';

            if (!$groups{$source}) {
                $groups{$source} = {
                    source_name   => $source,
                    source_label  =>
                        $source eq 'scopus'
                        ? 'Scopus'
                        : 'Web of Science',
                    source_icon   =>
                        $source eq 'scopus'
                        ? 'S'
                        : 'W',
                    profile_url   =>
                        $row->{profile_url} || '',
                    names         => [],
                };
            }

            push @{$groups{$source}->{names}}, {
                name_value        =>
                    $row->{name_value} || '',
                name_type         =>
                    $row->{name_type} || '',
                is_primary        =>
                    $row->{is_primary} ? 1 : 0,
                api_json_path     =>
                    $row->{api_json_path} || '',
                extraction_method =>
                    $row->{extraction_method} || '',
            };
        }

        for my $source (qw(scopus wos)) {
            push @source_name_groups,
                $groups{$source}
                if $groups{$source};
        }
    }

    $profile->{source_name_groups} =
        \@source_name_groups;

    $profile->{has_source_name_groups} =
        scalar(@source_name_groups) ? 1 : 0;
    # END ALL API AUTHOR NAME VARIANTS V11

    for my $publication (@{$unified_publications}) {
        if (
            $publication->{has_scopus}
            && (!$publication->{scopus_author_name}
                || $publication->{scopus_author_name} =~ /^\s*$/)
            && $author_identity_cache->{scopus}
        ) {
            $publication->{scopus_author_name} =
                $author_identity_cache->{scopus}->{published_name};
        }

        if (
            $publication->{has_wos}
            && (!$publication->{wos_author_name}
                || $publication->{wos_author_name} =~ /^\s*$/)
            && $author_identity_cache->{wos}
        ) {
            $publication->{wos_author_name} =
                $author_identity_cache->{wos}->{published_name};
        }

        $publication->{scopus_author_profile_url} =
            $author_identity_cache->{scopus}->{profile_url}
            if $author_identity_cache->{scopus};

        $publication->{wos_author_profile_url} =
            $author_identity_cache->{wos}->{profile_url}
            if $author_identity_cache->{wos};
        # END AUTHOR IDENTITY CACHE FALLBACK V10
        my $doi = $publication->{doi} || '';

        $doi =~ s/^\s+|\s+$//g;
        $doi =~ s{^https?://(?:dx\.)?doi\.org/}{}i;
        $doi =~ s/^doi:\s*//i;

        $publication->{doi} = $doi;

        $publication->{doi_url} =
            $doi
            ? "https://doi.org/$doi"
            : '';

        for my $field (
            qw(
                scopus_url
                wos_url
                crossref_url
            )
        ) {
            $publication->{$field} =
                safe_url($publication->{$field});
        }

        my @citation_values;

        for my $citation_field (
            qw(
                scopus_citations
                wos_citations
                crossref_citations
            )
        ) {
            my $value = $publication->{$citation_field};

            if (
                defined $value
                && $value ne ''
                && $value =~ /^\d+$/
            ) {
                push @citation_values, int($value);
            }
        }

        my $best_citation_count = 0;

        for my $value (@citation_values) {
            $best_citation_count = $value
                if $value > $best_citation_count;
        }

        $publication->{best_citation_count} =
            $best_citation_count;

        $total_citations += $best_citation_count;

        $scopus_count++
            if $publication->{has_scopus};

        $wos_count++
            if $publication->{has_wos};

        $crossref_count++
            if $publication->{has_crossref};

        if (
            $publication->{publication_year}
            && (
                !$latest_year
                || $publication->{publication_year} > $latest_year
            )
        ) {
            $latest_year =
                $publication->{publication_year};
        }

        if (
            $publication->{last_synced_at}
            && (
                !$last_synced
                || $publication->{last_synced_at} gt $last_synced
            )
        ) {
            $last_synced =
                $publication->{last_synced_at};
        }

        $publication->{search_text} = lc join(
            ' ',
            map { defined $_ ? $_ : '' }
            (
                $publication->{title},
                $publication->{journal},
                $publication->{doi},
                $publication->{document_type},
                $publication->{publication_year},
                $publication->{scopus_author_name},
                $publication->{wos_author_name},
                $publication->{crossref_author_name},
            )
        );
    }

    $unified_summary = {
        total_publications =>
            scalar @{$unified_publications},

        scopus_publications =>
            $scopus_count,

        wos_publications =>
            $wos_count,

        crossref_publications =>
            $crossref_count,

        total_citations =>
            $total_citations,

        latest_year =>
            $latest_year,

        last_synced =>
            $last_synced,
    };
}

$template->param(
    unified_publications =>
        $unified_publications,

    unified_summary =>
        $unified_summary,

    unified_publication_count =>
        scalar @{$unified_publications},
);

# END OPAC UNIFIED RESEARCH INTELLIGENCE


# BEGIN SOURCE PROFILE DISPLAY NAMES V1
#
# Display one API profile name per scholarly source.
# Publication-indexed forms such as "Kataria S." remain stored but are
# not used as the researcher profile display name.
#
my $source_profile_display_names = [];

if ($borrowernumber) {
    $source_profile_display_names =
        $dbh->selectall_arrayref(
            q{
                SELECT
                    c.source_name,

                    COALESCE(
                        (
                            SELECT v.name_value
                            FROM researcher_source_name_variants v
                            WHERE
                                v.borrowernumber =
                                    c.borrowernumber
                                AND v.source_name =
                                    c.source_name
                                AND
                                (
                                    (
                                        c.source_name =
                                            'scopus'
                                        AND v.name_type IN
                                        (
                                            'api-surname-given-components',
                                            'api-display-name'
                                        )
                                    )
                                    OR
                                    (
                                        c.source_name =
                                            'wos'
                                        AND v.name_type IN
                                        (
                                            'api-publication-display-name',
                                            'api-display-name'
                                        )
                                    )
                                )
                            ORDER BY
                                CASE
                                    WHEN
                                        c.source_name =
                                            'scopus'
                                        AND v.name_type =
                                            'api-surname-given-components'
                                    THEN 1

                                    WHEN
                                        c.source_name =
                                            'scopus'
                                        AND v.name_type =
                                            'api-display-name'
                                    THEN 2

                                    WHEN
                                        c.source_name =
                                            'wos'
                                        AND v.name_type =
                                            'api-publication-display-name'
                                    THEN 1

                                    WHEN
                                        c.source_name =
                                            'wos'
                                        AND v.name_type =
                                            'api-display-name'
                                    THEN 2

                                    ELSE 9
                                END,
                                v.is_primary DESC,
                                v.id
                            LIMIT 1
                        ),

                        NULLIF(TRIM(c.display_name), ''),
                        NULLIF(TRIM(c.published_name), '')
                    ) AS profile_display_name,

                    c.profile_url

                FROM researcher_author_identity_cache c
                WHERE c.borrowernumber = ?
                  AND c.source_name IN ('scopus', 'wos')
                ORDER BY
                    FIELD(c.source_name, 'scopus', 'wos')
            },
            { Slice => {} },
            $borrowernumber
        ) || [];
}

$template->param(
    source_profile_display_names =>
        $source_profile_display_names
);
# END SOURCE PROFILE DISPLAY NAMES V1

output_html_with_http_headers $query, $cookie, $template->output;
