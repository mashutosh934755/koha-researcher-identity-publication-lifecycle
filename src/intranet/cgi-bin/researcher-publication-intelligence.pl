#!/usr/bin/perl

use Modern::Perl;
use CGI qw(-utf8);
use C4::Auth qw(get_template_and_user);
use C4::Context;
use C4::Output qw(output_html_with_http_headers);

my $query = CGI->new;

my ( $template, $loggedinuser, $cookie ) =
    get_template_and_user(
        {
            template_name =>
                'tools/researcher-publication-intelligence.tt',
            query           => $query,
            type            => 'intranet',
            authnotrequired => 0,
            flagsrequired   => { tools => '*' },
        }
    );

my $dbh = C4::Context->dbh;

my $userenv = C4::Context->userenv || {};

my $staff_borrowernumber =
       $userenv->{number}
    || $loggedinuser
    || 0;

my $message = '';
my $error   = '';

sub param_text {
    my ($name) = @_;

    my $value = scalar $query->param($name);
    $value = '' unless defined $value;

    $value =~ s/^\s+//;
    $value =~ s/\s+$//;

    return $value;
}

sub valid_integer {
    my ($value) = @_;

    return defined $value
        && $value =~ /^\d+$/
        && $value > 0;
}

sub audit_action {
    my (%args) = @_;

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
                source
            )
            VALUES (?, ?, ?, ?, ?, ?, 'staff')
        },
        undef,
        $args{borrowernumber},
        $args{action_type},
        $args{old_value},
        $args{new_value},
        $args{reason},
        $staff_borrowernumber || undef
    );
}

if ($query->request_method eq 'POST') {

    my $action  = param_text('action');
    my $link_id = param_text('link_id');
    my $reason  = param_text('reason');

    my %allowed_actions = map { $_ => 1 } qw(
        confirm
        reject
        needs_review
    );

    if ($action eq '') {
        # Empty POST can occur when Enter is pressed inside the
        # review-reason field. Ignore it instead of showing an error.
    }
    elsif (!$allowed_actions{$action}) {
        $error = 'Invalid publication review action.';
    }
    elsif (!valid_integer($link_id)) {
        $error = 'Invalid publication-researcher link.';
    }
    else {
        my $link = $dbh->selectrow_hashref(
            q{
                SELECT
                    l.id,
                    l.borrowernumber,
                    l.publication_id,
                    l.source_name,
                    l.system_decision,
                    l.review_status,
                    l.match_score,
                    p.title,
                    p.doi
                FROM researcher_publication_links l
                JOIN researcher_publications_master p
                  ON p.id = l.publication_id
                WHERE l.id = ?
            },
            undef,
            $link_id
        );

        if (!$link) {
            $error = 'Publication link was not found.';
        }
        else {
            my $old_value = join(
                '; ',
                'system_decision='
                    . ($link->{system_decision} // ''),
                'review_status='
                    . ($link->{review_status} // ''),
                'match_score='
                    . ($link->{match_score} // '')
            );

            eval {
                $dbh->{AutoCommit} = 0;

                if ($action eq 'confirm') {
                    $dbh->do(
                        q{
                            UPDATE researcher_publication_links
                            SET
                                system_decision = 'confirmed',
                                review_status = 'manually_confirmed',
                                reviewed_by = ?,
                                reviewed_at = NOW(),
                                match_score =
                                    CASE
                                        WHEN match_score IS NULL
                                        THEN 100.00
                                        ELSE match_score
                                    END,
                                last_confirmed_at = NOW()
                            WHERE id = ?
                        },
                        undef,
                        $staff_borrowernumber || undef,
                        $link_id
                    );

                    audit_action(
                        borrowernumber =>
                            $link->{borrowernumber},
                        action_type =>
                            'publication_manually_confirmed',
                        old_value =>
                            $old_value,
                        new_value =>
                            'system_decision=confirmed; '
                            . 'review_status=manually_confirmed',
                        reason =>
                            $reason
                            || 'Confirmed by library staff',
                    );

                    $message =
                        'Publication attribution confirmed.';
                }
                elsif ($action eq 'reject') {
                    $dbh->do(
                        q{
                            UPDATE researcher_publication_links
                            SET
                                system_decision = 'rejected',
                                review_status = 'manually_rejected',
                                reviewed_by = ?,
                                reviewed_at = NOW()
                            WHERE id = ?
                        },
                        undef,
                        $staff_borrowernumber || undef,
                        $link_id
                    );

                    audit_action(
                        borrowernumber =>
                            $link->{borrowernumber},
                        action_type =>
                            'publication_manually_rejected',
                        old_value =>
                            $old_value,
                        new_value =>
                            'system_decision=rejected; '
                            . 'review_status=manually_rejected',
                        reason =>
                            $reason
                            || 'Rejected by library staff',
                    );

                    $message =
                        'Publication attribution rejected.';
                }
                elsif ($action eq 'needs_review') {
                    $dbh->do(
                        q{
                            UPDATE researcher_publication_links
                            SET
                                system_decision = 'review',
                                review_status = 'needs_review',
                                reviewed_by = ?,
                                reviewed_at = NOW()
                            WHERE id = ?
                        },
                        undef,
                        $staff_borrowernumber || undef,
                        $link_id
                    );

                    audit_action(
                        borrowernumber =>
                            $link->{borrowernumber},
                        action_type =>
                            'publication_flagged_for_review',
                        old_value =>
                            $old_value,
                        new_value =>
                            'system_decision=review; '
                            . 'review_status=needs_review',
                        reason =>
                            $reason
                            || 'Flagged for further evidence',
                    );

                    $message =
                        'Publication moved to review queue.';
                }

                $dbh->commit;
                $dbh->{AutoCommit} = 1;
            };

            if ($@) {
                my $failure = "$@";

                eval { $dbh->rollback };
                $dbh->{AutoCommit} = 1;

                $error = 'Review action failed: ' . $failure;
            }
        }
    }
}

my $summary = $dbh->selectrow_hashref(
    q{
        SELECT
            (
                SELECT COUNT(*)
                FROM custom_profile_details
            ) AS total_profiles,

            (
                SELECT COUNT(*)
                FROM custom_profile_details
                WHERE verification_status = 'verified'
                  AND employment_status = 'active'
            ) AS current_verified_researchers,

            (
                SELECT COUNT(*)
                FROM researcher_publications_master
            ) AS unique_publications,

            (
                SELECT COUNT(*)
                FROM researcher_publication_sources
                WHERE source_name = 'scopus'
            ) AS scopus_source_records,

            (
                SELECT COUNT(*)
                FROM researcher_publication_sources
                WHERE source_name = 'wos'
            ) AS wos_source_records,

            (
                SELECT COUNT(DISTINCT borrowernumber)
                FROM researcher_publication_links
                WHERE source_name = 'scopus'
                  AND system_decision = 'confirmed'
            ) AS researchers_with_scopus_publications,

            (
                SELECT COUNT(DISTINCT borrowernumber)
                FROM researcher_publication_links
                WHERE source_name = 'wos'
                  AND system_decision = 'confirmed'
            ) AS researchers_with_wos_publications,

            (
                SELECT COUNT(*)
                FROM researcher_publication_links
                WHERE system_decision = 'review'
                   OR review_status IN (
                       'unreviewed',
                       'needs_review'
                   )
            ) AS review_queue,

            (
                SELECT COUNT(*)
                FROM researcher_publication_links
                WHERE system_decision = 'rejected'
            ) AS rejected_links,

            (
                SELECT COUNT(*)
                FROM researcher_sync_jobs
                WHERE job_status = 'failed'
            ) AS failed_sync_jobs
    }
) || {};

my $source_summary = $dbh->selectall_arrayref(
    q{
        SELECT
            source_name,
            COUNT(*) AS source_records,
            COUNT(
                DISTINCT publication_id
            ) AS unique_publications,
            MAX(last_synced_at) AS last_synced_at
        FROM researcher_publication_sources
        GROUP BY source_name
        ORDER BY source_name
    },
    { Slice => {} }
) || [];

my $yearly = $dbh->selectall_arrayref(
    q{
        SELECT
            COALESCE(publication_year, 0)
                AS publication_year,
            COUNT(*) AS publications
        FROM researcher_publications_master
        GROUP BY COALESCE(publication_year, 0)
        ORDER BY publication_year DESC
        LIMIT 25
    },
    { Slice => {} }
) || [];

my $departments = $dbh->selectall_arrayref(
    q{
        SELECT
            COALESCE(
                NULLIF(TRIM(c.working_group), ''),
                '[Not assigned]'
            ) AS department,
            COUNT(
                DISTINCT c.borrowernumber
            ) AS researchers,
            COUNT(
                DISTINCT CASE
                    WHEN l.system_decision = 'confirmed'
                    THEN l.publication_id
                END
            ) AS confirmed_publications
        FROM custom_profile_details c
        LEFT JOIN researcher_publication_links l
          ON l.borrowernumber = c.borrowernumber
        WHERE c.verification_status = 'verified'
          AND c.employment_status = 'active'
        GROUP BY
            COALESCE(
                NULLIF(TRIM(c.working_group), ''),
                '[Not assigned]'
            )
        ORDER BY confirmed_publications DESC,
                 department ASC
    },
    { Slice => {} }
) || [];

my $researcher_output = $dbh->selectall_arrayref(
    q{
        SELECT
            c.borrowernumber,
            c.preferred_name,
            c.user_type,
            c.job_title,
            c.working_group,
            c.verification_status,
            c.employment_status,
            c.last_scopus_sync,
            c.last_wos_sync,

            COUNT(
                DISTINCT CASE
                    WHEN l.source_name = 'scopus'
                     AND l.system_decision = 'confirmed'
                    THEN l.publication_id
                END
            ) AS scopus_publications,

            COUNT(
                DISTINCT CASE
                    WHEN l.source_name = 'wos'
                     AND l.system_decision = 'confirmed'
                    THEN l.publication_id
                END
            ) AS wos_publications,

            COUNT(
                DISTINCT CASE
                    WHEN l.system_decision = 'confirmed'
                    THEN l.publication_id
                END
            ) AS unique_confirmed_publications,

            COUNT(
                DISTINCT CASE
                    WHEN l.system_decision = 'review'
                      OR l.review_status IN (
                          'unreviewed',
                          'needs_review'
                      )
                    THEN l.publication_id
                END
            ) AS review_items

        FROM custom_profile_details c

        LEFT JOIN researcher_publication_links l
          ON l.borrowernumber = c.borrowernumber

        GROUP BY
            c.borrowernumber,
            c.preferred_name,
            c.user_type,
            c.job_title,
            c.working_group,
            c.verification_status,
            c.employment_status,
            c.last_scopus_sync,
            c.last_wos_sync

        ORDER BY
            unique_confirmed_publications DESC,
            c.preferred_name ASC
    },
    { Slice => {} }
) || [];

my $status_filter = param_text('status');
my $source_filter = param_text('source');
my $search        = param_text('q');

my @where;
my @bind;

if ($status_filter eq 'confirmed') {
    push @where, q{l.system_decision = 'confirmed'};
}
elsif ($status_filter eq 'review') {
    push @where, q{
        (
            l.system_decision = 'review'
            OR l.review_status IN (
                'unreviewed',
                'needs_review'
            )
        )
    };
}
elsif ($status_filter eq 'rejected') {
    push @where, q{l.system_decision = 'rejected'};
}

if ($source_filter ne '') {
    push @where, q{l.source_name = ?};
    push @bind, $source_filter;
}

if ($search ne '') {
    my $like = '%' . $search . '%';

    push @where, q{
        (
            p.title LIKE ?
            OR p.doi LIKE ?
            OR p.journal LIKE ?
            OR c.preferred_name LIKE ?
            OR c.working_group LIKE ?
        )
    };

    push @bind, ($like) x 5;
}

my $where_sql = @where
    ? 'WHERE ' . join(' AND ', @where)
    : '';

my $links = $dbh->selectall_arrayref(
    qq{
        SELECT
            l.id AS link_id,
            l.borrowernumber,
            l.publication_id,
            l.source_name,
            l.source_author_id,
            l.affiliation_status,
            l.match_score,
            l.system_decision,
            l.review_status,
            l.reviewed_at,

            c.preferred_name,
            c.user_type,
            c.working_group,

            p.title,
            p.doi,
            p.journal,
            p.publication_date,
            p.publication_year,
            p.document_type,

            s.source_record_id,
            s.source_url,
            s.citation_count,
            s.last_synced_at

        FROM researcher_publication_links l

        JOIN custom_profile_details c
          ON c.borrowernumber = l.borrowernumber

        JOIN researcher_publications_master p
          ON p.id = l.publication_id

        LEFT JOIN researcher_publication_sources s
          ON s.publication_id = p.id
         AND s.source_name = l.source_name

        $where_sql

        ORDER BY
            CASE
                WHEN l.system_decision = 'review'
                  OR l.review_status IN (
                      'unreviewed',
                      'needs_review'
                  )
                THEN 1
                WHEN l.system_decision = 'rejected'
                THEN 2
                ELSE 3
            END,
            p.publication_date DESC,
            p.id DESC

        LIMIT 500
    },
    { Slice => {} },
    @bind
) || [];

my $duplicates = $dbh->selectall_arrayref(
    q{
        SELECT
            normalised_doi,
            COUNT(*) AS duplicate_count,
            GROUP_CONCAT(
                id ORDER BY id
                SEPARATOR ', '
            ) AS publication_ids,
            MIN(title) AS sample_title
        FROM researcher_publications_master
        WHERE COALESCE(normalised_doi, '') <> ''
        GROUP BY normalised_doi
        HAVING COUNT(*) > 1
        ORDER BY duplicate_count DESC
        LIMIT 100
    },
    { Slice => {} }
) || [];

my $sync_jobs = $dbh->selectall_arrayref(
    q{
        SELECT
            j.id,
            j.borrowernumber,
            j.source_name,
            j.job_type,
            j.job_status,
            j.records_found,
            j.records_processed,
            j.records_added,
            j.records_updated,
            j.records_linked,
            j.error_message,
            j.started_at,
            j.completed_at,
            c.preferred_name
        FROM researcher_sync_jobs j
        LEFT JOIN custom_profile_details c
          ON c.borrowernumber = j.borrowernumber
        ORDER BY j.id DESC
        LIMIT 50
    },
    { Slice => {} }
) || [];

$template->param(
    message           => $message,
    error             => $error,
    summary           => $summary,
    source_summary    => $source_summary,
    yearly            => $yearly,
    departments       => $departments,
    researcher_output => $researcher_output,
    links             => $links,
    duplicates        => $duplicates,
    sync_jobs         => $sync_jobs,
    status_filter     => $status_filter,
    source_filter     => $source_filter,
    q                 => $search,
);

output_html_with_http_headers(
    $query,
    $cookie,
    $template->output
);
