#!/usr/bin/perl

use Modern::Perl;
use CGI qw(-utf8);
use URI::Escape qw(uri_escape_utf8);

use C4::Auth qw(get_template_and_user);
use C4::Context;
use C4::Output qw(output_html_with_http_headers);

my $query = CGI->new;

my ( $template, $loggedinuser, $cookie ) =
    get_template_and_user(
        {
            template_name   => 'opac-researcher-search.tt',
            query           => $query,
            type            => 'opac',
            authnotrequired => 1,
        }
    );

my $dbh = C4::Context->dbh;

sub clean_param {
    my ( $name, $maximum ) = @_;

    my $value = $query->param($name) // '';

    $value =~ s/^\s+|\s+$//g;

    return substr(
        $value,
        0,
        $maximum
    );
}

sub encode_query_value {
    my ($value) = @_;

    return uri_escape_utf8(
        defined $value ? $value : ''
    );
}

my $q = clean_param( 'q', 200 );

my $status_filter =
    lc clean_param( 'status', 20 );

$status_filter = 'all'
    unless $status_filter =~ /^(?:all|current|former)$/;

my $type_filter =
    clean_param( 'type', 100 );

$type_filter = 'all'
    unless length $type_filter;

my $department_filter =
    clean_param( 'department', 255 );

$department_filter = 'all'
    unless length $department_filter;

my $school_filter =
    clean_param( 'school', 255 );

$school_filter = 'all'
    unless length $school_filter;

my $sort_filter =
    lc clean_param( 'sort', 30 );

$sort_filter = 'name_az'
    unless $sort_filter =~
        /^(?:name_az|name_za|recently_updated)$/;

my @where = (
    q{c.verification_status = 'verified'},
    q{c.public_visibility = 1},
    q{c.employment_status IN ('active', 'former')}
);

my @bind;

if ( $status_filter eq 'current' ) {
    push @where,
        q{c.employment_status = 'active'};
}
elsif ( $status_filter eq 'former' ) {
    push @where,
        q{c.employment_status = 'former'};
}

if ( $type_filter ne 'all' ) {
    push @where,
        q{TRIM(c.user_type) = ?};

    push @bind,
        $type_filter;
}

if ( $department_filter ne 'all' ) {
    push @where,
        q{TRIM(c.department) = ?};

    push @bind,
        $department_filter;
}

if ( $school_filter ne 'all' ) {
    push @where,
        q{TRIM(c.school) = ?};

    push @bind,
        $school_filter;
}

if ( length $q ) {
    my $like = '%' . $q . '%';

    push @where, q{
        (
               c.preferred_name LIKE ?
            OR c.official_name LIKE ?
            OR c.first_name LIKE ?
            OR c.last_name LIKE ?
            OR c.job_title LIKE ?
            OR c.designation LIKE ?
            OR c.main_affiliation LIKE ?
            OR c.department LIKE ?
            OR c.school LIKE ?
            OR c.working_group LIKE ?
            OR c.research_interests LIKE ?
            OR c.orcid LIKE ?
            OR c.scopus_author_id LIKE ?
            OR c.researcher_id LIKE ?
            OR c.employee_id LIKE ?
            OR b.firstname LIKE ?
            OR b.surname LIKE ?
            OR b.cardnumber LIKE ?
        )
    };

    push @bind,
        ($like) x 18;
}

my $display_name_sql = q{
    COALESCE(
        NULLIF(TRIM(c.preferred_name), ''),
        NULLIF(TRIM(c.official_name), ''),
        NULLIF(
            TRIM(
                CONCAT_WS(
                    ' ',
                    NULLIF(TRIM(b.firstname), ''),
                    NULLIF(TRIM(b.surname), '')
                )
            ),
            ''
        ),
        b.cardnumber
    )
};

my $order_sql;

if ( $sort_filter eq 'name_za' ) {
    $order_sql = "$display_name_sql DESC";
}
elsif ( $sort_filter eq 'recently_updated' ) {
    $order_sql = q{
        c.updated_at DESC,
    } . "$display_name_sql ASC";
}
else {
    $order_sql = "$display_name_sql ASC";
}

# RIMS_PUBLIC_UNIQUE_PUBLICATION_COUNT_V1
my $sql = q{
    SELECT
        c.borrowernumber,
        c.researcher_uuid,
        c.preferred_name,
        c.official_name,
        c.first_name,
        c.last_name,
        c.job_title,
        c.designation,
        c.main_affiliation,
        c.department,
        c.school,
        c.working_group,
        c.research_interests,
        c.user_type,
        c.orcid,
        c.scopus_author_id,
        c.researcher_id,
        c.verification_status,
        c.employment_status,
        c.public_visibility,
        c.sync_enabled,
        c.relieving_date,
        c.updated_at,
        b.firstname,
        b.surname,
        b.cardnumber,

        (
            SELECT COUNT(DISTINCT piv.publication_id)
            FROM researcher_publication_identity_v piv
            WHERE piv.researcher_uuid = c.researcher_uuid
        ) AS publication_count

    FROM custom_profile_details c
    JOIN borrowers b
      ON b.borrowernumber = c.borrowernumber
    WHERE
} . join( "\n AND ", @where ) . q{
    ORDER BY
        CASE
            WHEN c.employment_status = 'active'
                THEN 1
            WHEN c.employment_status = 'former'
                THEN 2
            ELSE 3
        END,
} . $order_sql . q{
    LIMIT 500
};

my $rows = $dbh->selectall_arrayref(
    $sql,
    { Slice => {} },
    @bind
) || [];

sub option_rows {
    my (%args) = @_;

    my $column = $args{column};
    my $selected_value =
        $args{selected_value} // 'all';

    die 'Invalid option column'
        unless $column =~
            /^(?:user_type|department|school)$/;

    my $sql = qq{
        SELECT
            TRIM($column) AS option_value,
            COUNT(*) AS profile_count
        FROM custom_profile_details
        WHERE verification_status = 'verified'
          AND public_visibility = 1
          AND employment_status IN ('active', 'former')
          AND $column IS NOT NULL
          AND TRIM($column) <> ''
        GROUP BY TRIM($column)
        ORDER BY TRIM($column)
    };

    my $database_rows =
        $dbh->selectall_arrayref(
            $sql,
            { Slice => {} }
        ) || [];

    my @options;

    for my $row ( @{$database_rows} ) {
        my $value =
            $row->{option_value} // '';

        next unless length $value;

        push @options, {
            value         => $value,
            label         => $value,
            profile_count =>
                $row->{profile_count} // 0,
            selected      => (
                   $selected_value ne 'all'
                && $selected_value eq $value
            ) ? 1 : 0,
        };
    }

    return \@options;
}

my $researcher_types = option_rows(
    column         => 'user_type',
    selected_value => $type_filter,
);

my $departments = option_rows(
    column         => 'department',
    selected_value => $department_filter,
);

my $schools = option_rows(
    column         => 'school',
    selected_value => $school_filter,
);

my @current_results;
my @former_results;

for my $row ( @{$rows} ) {

    my $display_name =
           $row->{preferred_name}
        || $row->{official_name}
        || join(
            ' ',
            grep {
                defined $_
                && length $_
            } (
                $row->{firstname},
                $row->{surname}
            )
        )
        || $row->{cardnumber}
        || 'Researcher';

    my $designation =
           $row->{designation}
        || $row->{job_title}
        || $row->{user_type}
        || '';

    my @unit_candidates = (
        $row->{department},
        $row->{school},
        $row->{working_group},
        $row->{main_affiliation},
    );

    my $institution_line = '';

    for my $candidate (@unit_candidates) {
        next unless defined $candidate;

        $candidate =~ s/^\s+|\s+$//g;

        next unless length $candidate;
        my $institution_name = lc($ENV{RIMS_INSTITUTION_NAME} || 'Example University');
        next if $institution_name !~ /^__/
            && lc($candidate) eq $institution_name;

        $institution_line = $candidate;
        last;
    }

    my $initial =
        uc substr( $display_name, 0, 1 );

    $initial = 'R'
        unless $initial =~ /[[:alnum:]]/;

    $row->{display_name} =
        $display_name;

    $row->{initial} =
        $initial;

    $row->{display_designation} =
        $designation;

    $row->{institution_line} =
        $institution_line;

    # BEGIN RESEARCHER DIRECTORY EXPERTISE V6
    #
    # research_interests is stored as multiline text.
    # Convert it into a concise, deduplicated set of tags
    # for researcher discovery cards.
    #
    my @expertise_tags;
    my %expertise_seen;

    my $research_interests =
        $row->{research_interests} // '';

    for my $interest (
        split /(?:\r?\n|;)+/,
        $research_interests
    ) {

        $interest =~ s/^\s+|\s+$//g;
        $interest =~ s/\s+/ /g;

        next unless length $interest;

        my $key = lc $interest;

        next if $expertise_seen{$key}++;

        # Avoid excessively long card chips.
        if ( length($interest) > 60 ) {
            $interest =
                substr($interest, 0, 57)
                . '...';
        }

        push @expertise_tags,
            $interest;

        last if @expertise_tags >= 6;
    }

    $row->{expertise_tags} =
        \@expertise_tags;

    $row->{has_expertise} =
        @expertise_tags ? 1 : 0;

    $row->{publication_count} =
        $row->{publication_count} || 0;

    # END RESEARCHER DIRECTORY EXPERTISE V6

    if ( $row->{orcid} ) {
        my $orcid = $row->{orcid};

        $orcid =~ s{
            ^https?://orcid\.org/
        }{}ix;

        $row->{orcid_clean} = $orcid;
        $row->{orcid_url} =
            'https://orcid.org/'
            . uri_escape_utf8($orcid);
    }

    if ( $row->{scopus_author_id} ) {
        my $scopus_id =
            $row->{scopus_author_id};

        $scopus_id =~ s/\D//g;

        if ( length $scopus_id ) {
            $row->{scopus_url} =
                'https://www.scopus.com/authid/'
                . 'detail.uri?authorId='
                . uri_escape_utf8($scopus_id);
        }
    }

    if ( $row->{researcher_id} ) {
        $row->{wos_url} =
            'https://www.webofscience.com/wos/'
            . 'author/record/'
            . uri_escape_utf8(
                $row->{researcher_id}
            );
    }

    if (
        ($row->{employment_status} // '')
        eq 'former'
    ) {
        push @former_results,
            $row;
    }
    else {
        push @current_results,
            $row;
    }
}

my $count_row =
    $dbh->selectrow_hashref(
        q{
            SELECT
                SUM(
                    verification_status = 'verified'
                    AND public_visibility = 1
                    AND employment_status = 'active'
                ) AS current_count,

                SUM(
                    verification_status = 'verified'
                    AND public_visibility = 1
                    AND employment_status = 'former'
                ) AS former_count,

                SUM(
                    verification_status = 'verified'
                    AND public_visibility = 1
                    AND employment_status IN (
                        'active',
                        'former'
                    )
                ) AS total_count,

                SUM(
                    verification_status = 'verified'
                    AND public_visibility = 1
                    AND orcid IS NOT NULL
                    AND TRIM(orcid) <> ''
                ) AS orcid_count,

                SUM(
                    verification_status = 'verified'
                    AND public_visibility = 1
                    AND scopus_author_id IS NOT NULL
                    AND TRIM(scopus_author_id) <> ''
                ) AS scopus_count,

                SUM(
                    verification_status = 'verified'
                    AND public_visibility = 1
                    AND researcher_id IS NOT NULL
                    AND TRIM(researcher_id) <> ''
                ) AS wos_count
            FROM custom_profile_details
        }
    ) || {};

# BEGIN RESEARCHER DIRECTORY PUBLICATION KPI V6

my $total_publication_links =
    $dbh->selectrow_array(
        q{
            SELECT COUNT(DISTINCT piv.publication_id)

            FROM researcher_publication_identity_v piv

            JOIN custom_profile_details c
              ON c.researcher_uuid =
                 piv.researcher_uuid

            WHERE c.verification_status='verified'
              AND c.public_visibility=1
              AND c.employment_status IN (
                    'active',
                    'former'
              )
        }
    ) || 0;

# END RESEARCHER DIRECTORY PUBLICATION KPI V6

my $result_count =
      scalar @current_results
    + scalar @former_results;

my $has_filters =
       length($q)
    || $status_filter ne 'all'
    || $type_filter ne 'all'
    || $department_filter ne 'all'
    || $school_filter ne 'all'
    || $sort_filter ne 'name_az';

$template->param(
    q                    => $q,

    status_filter        => $status_filter,
    type_filter          => $type_filter,
    department_filter    => $department_filter,
    school_filter        => $school_filter,
    sort_filter          => $sort_filter,

    researcher_types     => $researcher_types,
    departments          => $departments,
    schools              => $schools,

    has_query            =>
        length($q) ? 1 : 0,

    has_filters          =>
        $has_filters ? 1 : 0,

    has_type_filter      =>
        $type_filter ne 'all' ? 1 : 0,

    has_department_filter =>
        $department_filter ne 'all'
            ? 1
            : 0,

    has_school_filter    =>
        $school_filter ne 'all'
            ? 1
            : 0,

    current_results      =>
        \@current_results,

    former_results       =>
        \@former_results,

    current_result_count =>
        scalar @current_results,

    former_result_count  =>
        scalar @former_results,

    result_count         =>
        $result_count,

    current_count        =>
        $count_row->{current_count} // 0,

    total_publication_links =>
        $total_publication_links,

    former_count         =>
        $count_row->{former_count} // 0,

    total_count          =>
        $count_row->{total_count} // 0,

    orcid_count          =>
        $count_row->{orcid_count} // 0,

    scopus_count         =>
        $count_row->{scopus_count} // 0,

    wos_count            =>
        $count_row->{wos_count} // 0,

    q_url                =>
        encode_query_value($q),

    type_url             =>
        encode_query_value($type_filter),

    department_url       =>
        encode_query_value(
            $department_filter
        ),

    school_url           =>
        encode_query_value($school_filter),

    sort_url             =>
        encode_query_value($sort_filter),
);

output_html_with_http_headers(
    $query,
    $cookie,
    $template->output
);
