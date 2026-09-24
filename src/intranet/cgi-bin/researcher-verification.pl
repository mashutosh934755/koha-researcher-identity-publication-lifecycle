#!/usr/bin/perl

# RESEARCHER_REMOVE_DELETE_V6

use Modern::Perl;
use CGI qw(-utf8);
use C4::Auth qw(get_template_and_user);
use C4::Context;
use C4::Output qw(output_html_with_http_headers);
use Koha::Token;

my $query = CGI->new;

my ( $template, $loggedinuser, $cookie ) =
    get_template_and_user(
        {
            template_name   => 'tools/researcher-verification.tt',
            query           => $query,
            type            => 'intranet',
            authnotrequired => 0,
            flagsrequired   => { tools => '*' },
        }
    );

my $dbh = C4::Context->dbh;

my $session_id =
    scalar $query->cookie('CGISESSID')
    || '';

my $csrf_token = Koha::Token->new->generate_csrf(
    {
        session_id => $session_id,
    }
);

my $PROFILE_URL = '/cgi-bin/koha/opac-researcher-profile.pl';

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

sub valid_borrowernumber {
    my ($value) = @_;

    return defined $value
        && $value =~ /^\d+$/
        && $value > 0;
}


# RIMS_CORE_MANAGEMENT_V1

sub valid_optional_date {
    my ($value) = @_;

    return 1 if !defined $value || $value eq '';

    return $value =~ /^\d{4}-\d{2}-\d{2}$/;
}

sub checkbox_value {
    my ($name) = @_;

    my $value = scalar $query->param($name);

    return defined $value && $value eq '1' ? 1 : 0;
}


# RIMS_IDENTIFIERS_MODULE_V1

sub valid_identifier_type {
    my ($value) = @_;

    return $value =~ /^(?:orcid|scopus|wos|google_scholar)$/;
}

sub valid_identifier_status {
    my ($value) = @_;

    return $value =~ /^(?:pending|verified|rejected)$/;
}

sub valid_identifier_value {
    my ($type, $value) = @_;

    return 0 if !defined $value || $value eq '';

    if ($type eq 'orcid') {
        return $value =~ /^\d{4}-\d{4}-\d{4}-\d{3}[\dX]$/;
    }

    if ($type eq 'scopus') {
        return $value =~ /^\d{8,12}$/;
    }

    if ($type eq 'wos') {
        return $value =~ /^[A-Za-z0-9][A-Za-z0-9_-]{2,49}$/;
    }

    if ($type eq 'google_scholar') {
        return $value =~ /^[A-Za-z0-9_-]{5,100}$/;
    }

    return 0;
}

sub identifier_type_label {
    my ($type) = @_;

    return 'ORCID iD'                if $type eq 'orcid';
    return 'Scopus Author ID'        if $type eq 'scopus';
    return 'Web of Science ID'       if $type eq 'wos';
    return 'Google Scholar Profile'  if $type eq 'google_scholar';

    return $type;
}


# RIMS_AFFILIATIONS_MODULE_V1

sub valid_affiliation_type {
    my ($value) = @_;

    return $value =~ /^(?:employment|education|research|visiting|honorary|other)$/;
}

sub valid_affiliation_status {
    my ($value) = @_;

    return $value =~ /^(?:pending|verified|rejected)$/;
}

sub affiliation_type_label {
    my ($value) = @_;

    return 'Employment' if $value eq 'employment';
    return 'Education'  if $value eq 'education';
    return 'Research'   if $value eq 'research';
    return 'Visiting'   if $value eq 'visiting';
    return 'Honorary'   if $value eq 'honorary';
    return 'Other'      if $value eq 'other';

    return $value;
}

# RIMS_NAME_VARIANTS_MODULE_V1

sub normalise_name_variant {
    my ($value) = @_;

    $value = '' unless defined $value;
    $value = lc $value;
    $value =~ s/[^\p{L}\p{N}]+/ /g;
    $value =~ s/^\s+|\s+$//g;
    $value =~ s/\s+/ /g;

    return $value;
}

sub valid_variant_source {
    my ($value) = @_;

    return $value =~ /^(?:manual|profile|publication|orcid|scopus|wos|import)$/;
}

sub profile_exists {
    my ($borrowernumber) = @_;

    return $dbh->selectrow_array(
        'SELECT COUNT(*)
         FROM custom_profile_details
         WHERE borrowernumber = ?',
        undef,
        $borrowernumber
    ) || 0;
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

    my $submitted_csrf_token =
        param_text('csrf_token');

    my $csrf_is_valid =
           $session_id ne ''
        && $submitted_csrf_token ne ''
        && Koha::Token->new->check_csrf(
            {
                session_id => $session_id,
                token      => $submitted_csrf_token,
            }
        );

    if (!$csrf_is_valid) {
        $template->param(
            error =>
                'The security token is invalid or has expired. '
                . 'Please reload the page and try again.',
            csrf_token => $csrf_token,
        );

        output_html_with_http_headers(
            $query,
            $cookie,
            $template->output
        );

        exit;
    }

    my $action         = param_text('action');
    my $borrowernumber = param_text('borrowernumber');
    my $reason         = param_text('reason');

    # RESEARCHER_REMOVE_DELETE_V6
    my $confirmation_name =
        param_text('confirmation_name');
    my $delete_acknowledged =
        checkbox_value('delete_acknowledged');

    my $preferred_name   = param_text('preferred_name');
    my $official_name    = param_text('official_name');
    my $user_type        = param_text('profile_user_type');
    my $department       = param_text('department');
    my $school           = param_text('school');
    my $designation      = param_text('designation');
    my $employee_id      = param_text('employee_id');
    my $joining_date     = param_text('joining_date');
    my $employment_input = param_text('employment_status');
    my $public_input     = checkbox_value('public_visibility');
    my $sync_input       = checkbox_value('sync_enabled');

    my $identifier_id     = param_text('identifier_id');
    my $identifier_type   = lc param_text('identifier_type');
    my $identifier_value  = param_text('identifier_value');
    my $identifier_status = lc param_text('identifier_status');
    my $identifier_source = param_text('identifier_source');
    my $identifier_primary = checkbox_value('identifier_primary');
    my $identifier_active  = checkbox_value('identifier_active');

    my $affiliation_id         = param_text('affiliation_id');
    my $affiliation_org        = param_text('affiliation_organisation');
    my $affiliation_org_id     = param_text('affiliation_organisation_id');
    my $affiliation_department = param_text('affiliation_department');
    my $affiliation_role       = param_text('affiliation_role');
    my $affiliation_start      = param_text('affiliation_start_date');
    my $affiliation_end        = param_text('affiliation_end_date');
    my $affiliation_type       = lc param_text('affiliation_type');
    my $affiliation_status     = lc param_text('affiliation_status');
    my $affiliation_source     = param_text('affiliation_source');
    my $affiliation_current    = checkbox_value('affiliation_current');

    my $variant_id       = param_text('variant_id');
    my $variant_name     = param_text('variant_name');
    my $variant_source   = lc param_text('variant_source');
    my $variant_verified = checkbox_value('variant_verified');

    my %allowed_actions = map { $_ => 1 } qw(
        verify
        reject
        mark_former
        reactivate
        hide_profile
        restore_profile
        delete_profile
        save_profile
        save_identifier
        save_affiliation
        save_name_variant
        delete_name_variant
        toggle_name_variant
    );

    if (!$allowed_actions{$action}) {
        $error = 'Invalid verification action.';
    }
    elsif (!valid_borrowernumber($borrowernumber)) {
        $error = 'Invalid researcher record.';
    }
    elsif (!profile_exists($borrowernumber)) {
        $error = 'Researcher profile does not exist.';
    }
    elsif (
           $action eq 'delete_profile'
        && $reason eq ''
    ) {
        $error =
            'A deletion reason is mandatory.';
    }
    elsif (
           $action eq 'delete_profile'
        && !$delete_acknowledged
    ) {
        $error =
            'Permanent deletion acknowledgement is required.';
    }
    elsif (
           $action eq 'delete_profile'
        && $confirmation_name eq ''
    ) {
        $error =
            'Type the researcher name to confirm permanent deletion.';
    }
    elsif (
           $action eq 'save_profile'
        && $preferred_name eq ''
    ) {
        $error = 'Preferred name is required.';
    }
    elsif (
           $action eq 'save_profile'
        && !valid_optional_date($joining_date)
    ) {
        $error = 'Joining date must use YYYY-MM-DD format.';
    }
    elsif (
           $action eq 'save_profile'
        && $employment_input !~ /^(?:active|former)$/
    ) {
        $error = 'Invalid employment status.';
    }
    elsif (
           $action eq 'save_identifier'
        && !valid_identifier_type($identifier_type)
    ) {
        $error = 'Invalid identifier type.';
    }
    elsif (
           $action eq 'save_identifier'
        && !valid_identifier_status($identifier_status)
    ) {
        $error = 'Invalid identifier verification status.';
    }
    elsif (
           $action eq 'save_identifier'
        && !valid_identifier_value(
            $identifier_type,
            $identifier_value
        )
    ) {
        $error =
            'The identifier value does not match the selected identifier type.';
    }
    elsif (
           $action eq 'save_identifier'
        && $identifier_id ne ''
        && $identifier_id !~ /^\d+$/
    ) {
        $error = 'Invalid identifier record.';
    }
    elsif (
           $action eq 'save_name_variant'
        && $variant_name eq ''
    ) {
        $error = 'Name variant is required.';
    }
    elsif (
           $action eq 'save_name_variant'
        && length($variant_name) > 255
    ) {
        $error = 'Name variant cannot exceed 255 characters.';
    }
    elsif (
           $action eq 'save_name_variant'
        && !valid_variant_source($variant_source)
    ) {
        $error = 'Invalid name-variant source.';
    }
    elsif (
           $action =~ /^(?:save_name_variant|delete_name_variant|toggle_name_variant)$/
        && $variant_id ne ''
        && $variant_id !~ /^\d+$/
    ) {
        $error = 'Invalid name-variant record.';
    }
    elsif (
           $action =~ /^(?:delete_name_variant|toggle_name_variant)$/
        && $variant_id eq ''
    ) {
        $error = 'Name-variant record is required.';
    }
    elsif (
           $action eq 'save_affiliation'
        && $affiliation_org eq ''
    ) {
        $error = 'Organisation name is required.';
    }
    elsif (
           $action eq 'save_affiliation'
        && !valid_affiliation_type($affiliation_type)
    ) {
        $error = 'Invalid affiliation type.';
    }
    elsif (
           $action eq 'save_affiliation'
        && !valid_affiliation_status($affiliation_status)
    ) {
        $error = 'Invalid affiliation verification status.';
    }
    elsif (
           $action eq 'save_affiliation'
        && !valid_optional_date($affiliation_start)
    ) {
        $error = 'Affiliation start date must use YYYY-MM-DD format.';
    }
    elsif (
           $action eq 'save_affiliation'
        && !valid_optional_date($affiliation_end)
    ) {
        $error = 'Affiliation end date must use YYYY-MM-DD format.';
    }
    elsif (
           $action eq 'save_affiliation'
        && $affiliation_start ne ''
        && $affiliation_end ne ''
        && $affiliation_start gt $affiliation_end
    ) {
        $error = 'Affiliation end date cannot be earlier than start date.';
    }
    elsif (
           $action eq 'save_affiliation'
        && $affiliation_current
        && $affiliation_end ne ''
    ) {
        $error = 'A current affiliation cannot have an end date.';
    }
    elsif (
           $action eq 'save_affiliation'
        && $affiliation_id ne ''
        && $affiliation_id !~ /^\d+$/
    ) {
        $error = 'Invalid affiliation record.';
    }
    else {
        my $old = $dbh->selectrow_hashref(
            q{
                SELECT
                    profile_status,
                    verification_status,
                    employment_status,
                    public_visibility,
                    sync_enabled,
                    relieving_date,
                    preferred_name,
                    official_name,
                    user_type,
                    department,
                    school,
                    designation,
                    employee_id,
                    joining_date
                FROM custom_profile_details
                WHERE borrowernumber = ?
            },
            undef,
            $borrowernumber
        ) || {};

        my $old_value = join(
            '; ',
            'profile_status='
                . ($old->{profile_status} // ''),
            'verification_status='
                . ($old->{verification_status} // ''),
            'employment_status='
                . ($old->{employment_status} // ''),
            'public_visibility='
                . ($old->{public_visibility} // ''),
            'sync_enabled='
                . ($old->{sync_enabled} // ''),
            'relieving_date='
                . ($old->{relieving_date} // ''),
            'preferred_name='
                . ($old->{preferred_name} // ''),
            'official_name='
                . ($old->{official_name} // ''),
            'user_type='
                . ($old->{user_type} // ''),
            'department='
                . ($old->{department} // ''),
            'school='
                . ($old->{school} // ''),
            'designation='
                . ($old->{designation} // ''),
            'employee_id='
                . ($old->{employee_id} // ''),
            'joining_date='
                . ($old->{joining_date} // '')
        );

        eval {
            $dbh->{AutoCommit} = 0;

            if ($action eq 'save_name_variant') {

                my $normalised_variant = normalise_name_variant($variant_name);

                die 'Name variant is invalid after normalization.'
                    if $normalised_variant eq '';

                if ($variant_id ne '') {
                    my $owned_variant = $dbh->selectrow_hashref(
                        q{
                            SELECT id, name_variant, normalised_variant,
                                   source, is_verified
                            FROM researcher_name_variants
                            WHERE id = ? AND borrowernumber = ?
                        },
                        undef,
                        $variant_id,
                        $borrowernumber
                    );

                    die 'Name-variant record does not belong to this researcher.'
                        if !$owned_variant;

                    $dbh->do(
                        q{
                            UPDATE researcher_name_variants
                            SET name_variant = ?,
                                normalised_variant = ?,
                                source = ?,
                                is_verified = ?,
                                verified_by = CASE WHEN ? = 1 THEN ? ELSE NULL END,
                                verified_at = CASE
                                    WHEN ? = 1 THEN COALESCE(verified_at, NOW())
                                    ELSE NULL
                                END,
                                updated_at = NOW()
                            WHERE id = ? AND borrowernumber = ?
                        },
                        undef,
                        $variant_name,
                        $normalised_variant,
                        $variant_source,
                        $variant_verified,
                        $variant_verified,
                        $staff_borrowernumber || undef,
                        $variant_verified,
                        $variant_id,
                        $borrowernumber
                    );

                    audit_action(
                        borrowernumber => $borrowernumber,
                        action_type    => 'name_variant_updated',
                        old_value      => join('; ',
                            'name=' . ($owned_variant->{name_variant} // ''),
                            'normalised=' . ($owned_variant->{normalised_variant} // ''),
                            'source=' . ($owned_variant->{source} // ''),
                            'verified=' . ($owned_variant->{is_verified} // 0)
                        ),
                        new_value      => join('; ',
                            'name=' . $variant_name,
                            'normalised=' . $normalised_variant,
                            'source=' . $variant_source,
                            'verified=' . $variant_verified
                        ),
                        reason => $reason || 'Name variant updated by library staff'
                    );

                    $message = 'Name variant updated successfully.';
                }
                else {
                    $dbh->do(
                        q{
                            INSERT INTO researcher_name_variants
                            (borrowernumber, name_variant, normalised_variant,
                             source, is_verified, verified_by, verified_at)
                            VALUES (?, ?, ?, ?, ?,
                                CASE WHEN ? = 1 THEN ? ELSE NULL END,
                                CASE WHEN ? = 1 THEN NOW() ELSE NULL END)
                        },
                        undef,
                        $borrowernumber,
                        $variant_name,
                        $normalised_variant,
                        $variant_source,
                        $variant_verified,
                        $variant_verified,
                        $staff_borrowernumber || undef,
                        $variant_verified
                    );

                    audit_action(
                        borrowernumber => $borrowernumber,
                        action_type    => 'name_variant_added',
                        old_value      => '',
                        new_value      => join('; ',
                            'name=' . $variant_name,
                            'normalised=' . $normalised_variant,
                            'source=' . $variant_source,
                            'verified=' . $variant_verified
                        ),
                        reason => $reason || 'Name variant added by library staff'
                    );

                    $message = 'Name variant added successfully.';
                }
            }
            elsif ($action eq 'delete_name_variant') {
                my $owned_variant = $dbh->selectrow_hashref(
                    q{
                        SELECT id, name_variant, normalised_variant,
                               source, is_verified
                        FROM researcher_name_variants
                        WHERE id = ? AND borrowernumber = ?
                    },
                    undef,
                    $variant_id,
                    $borrowernumber
                );

                die 'Name-variant record does not belong to this researcher.'
                    if !$owned_variant;

                $dbh->do(
                    'DELETE FROM researcher_name_variants WHERE id = ? AND borrowernumber = ?',
                    undef,
                    $variant_id,
                    $borrowernumber
                );

                audit_action(
                    borrowernumber => $borrowernumber,
                    action_type    => 'name_variant_deleted',
                    old_value      => join('; ',
                        'name=' . ($owned_variant->{name_variant} // ''),
                        'normalised=' . ($owned_variant->{normalised_variant} // ''),
                        'source=' . ($owned_variant->{source} // ''),
                        'verified=' . ($owned_variant->{is_verified} // 0)
                    ),
                    new_value => '',
                    reason => $reason || 'Name variant deleted by library staff'
                );

                $message = 'Name variant deleted successfully.';
            }
            elsif ($action eq 'toggle_name_variant') {
                my $owned_variant = $dbh->selectrow_hashref(
                    q{
                        SELECT id, name_variant, is_verified
                        FROM researcher_name_variants
                        WHERE id = ? AND borrowernumber = ?
                    },
                    undef,
                    $variant_id,
                    $borrowernumber
                );

                die 'Name-variant record does not belong to this researcher.'
                    if !$owned_variant;

                my $new_verified = $owned_variant->{is_verified} ? 0 : 1;

                $dbh->do(
                    q{
                        UPDATE researcher_name_variants
                        SET is_verified = ?,
                            verified_by = CASE WHEN ? = 1 THEN ? ELSE NULL END,
                            verified_at = CASE WHEN ? = 1 THEN NOW() ELSE NULL END,
                            updated_at = NOW()
                        WHERE id = ? AND borrowernumber = ?
                    },
                    undef,
                    $new_verified,
                    $new_verified,
                    $staff_borrowernumber || undef,
                    $new_verified,
                    $variant_id,
                    $borrowernumber
                );

                audit_action(
                    borrowernumber => $borrowernumber,
                    action_type    => $new_verified
                        ? 'name_variant_verified'
                        : 'name_variant_unverified',
                    old_value      => 'verified=' . ($owned_variant->{is_verified} // 0),
                    new_value      => 'verified=' . $new_verified,
                    reason => $reason || 'Name variant verification changed by library staff'
                );

                $message = $new_verified
                    ? 'Name variant verified.'
                    : 'Name variant marked unverified.';
            }
            elsif ($action eq 'save_affiliation') {

                if ($affiliation_current) {
                    $dbh->do(
                        q{
                            UPDATE researcher_affiliations
                            SET
                                is_current = 0,
                                end_date = COALESCE(
                                    end_date,
                                    CURDATE()
                                ),
                                updated_at = NOW()
                            WHERE borrowernumber = ?
                              AND is_current = 1
                              AND (? = '' OR id <> ?)
                        },
                        undef,
                        $borrowernumber,
                        $affiliation_id,
                        $affiliation_id || 0
                    );
                }

                if ($affiliation_id ne '') {

                    my $owned_affiliation =
                        $dbh->selectrow_hashref(
                            q{
                                SELECT
                                    id AS affiliation_id,
                                    organisation_name,
                                    organisation_identifier,
                                    department,
                                    role_title,
                                    start_date,
                                    end_date,
                                    is_current,
                                    affiliation_type,
                                    verification_status,
                                    source
                                FROM researcher_affiliations
                                WHERE id = ?
                                  AND borrowernumber = ?
                            },
                            undef,
                            $affiliation_id,
                            $borrowernumber
                        );

                    if (!$owned_affiliation) {
                        die
                            'Affiliation record does not belong to this researcher.';
                    }

                    my $old_affiliation_value = join(
                        '; ',
                        'organisation='
                            . ($owned_affiliation->{organisation_name} // ''),
                        'organisation_id='
                            . ($owned_affiliation->{organisation_identifier} // ''),
                        'department='
                            . ($owned_affiliation->{department} // ''),
                        'role='
                            . ($owned_affiliation->{role_title} // ''),
                        'start='
                            . ($owned_affiliation->{start_date} // ''),
                        'end='
                            . ($owned_affiliation->{end_date} // ''),
                        'current='
                            . ($owned_affiliation->{is_current} // 0),
                        'type='
                            . ($owned_affiliation->{affiliation_type} // ''),
                        'status='
                            . ($owned_affiliation->{verification_status} // ''),
                        'source='
                            . ($owned_affiliation->{source} // '')
                    );

                    $dbh->do(
                        q{
                            UPDATE researcher_affiliations
                            SET
                                organisation_name       = ?,
                                organisation_identifier = NULLIF(?, ''),
                                department              = NULLIF(?, ''),
                                role_title              = NULLIF(?, ''),
                                start_date              = NULLIF(?, ''),
                                end_date                =
                                    CASE
                                        WHEN ? = 1
                                        THEN NULL
                                        ELSE NULLIF(?, '')
                                    END,
                                is_current              = ?,
                                affiliation_type        = ?,
                                verification_status     = ?,
                                verified_by             =
                                    CASE
                                        WHEN ? = 'verified'
                                        THEN ?
                                        ELSE NULL
                                    END,
                                verified_at             =
                                    CASE
                                        WHEN ? = 'verified'
                                        THEN COALESCE(
                                            verified_at,
                                            NOW()
                                        )
                                        ELSE NULL
                                    END,
                                source                  = ?,
                                updated_at              = NOW()
                            WHERE id = ?
                              AND borrowernumber = ?
                        },
                        undef,
                        $affiliation_org,
                        $affiliation_org_id,
                        $affiliation_department,
                        $affiliation_role,
                        $affiliation_start,
                        $affiliation_current,
                        $affiliation_end,
                        $affiliation_current,
                        $affiliation_type,
                        $affiliation_status,
                        $affiliation_status,
                        $staff_borrowernumber || undef,
                        $affiliation_status,
                        $affiliation_source || 'staff-review',
                        $affiliation_id,
                        $borrowernumber
                    );

                    audit_action(
                        borrowernumber => $borrowernumber,
                        action_type    => 'affiliation_updated',
                        old_value      => $old_affiliation_value,
                        new_value      => join(
                            '; ',
                            'organisation=' . $affiliation_org,
                            'organisation_id=' . $affiliation_org_id,
                            'department=' . $affiliation_department,
                            'role=' . $affiliation_role,
                            'start=' . $affiliation_start,
                            'end=' . $affiliation_end,
                            'current=' . $affiliation_current,
                            'type=' . $affiliation_type,
                            'status=' . $affiliation_status,
                            'source=' . $affiliation_source
                        ),
                        reason => $reason
                            || 'Researcher affiliation updated by staff',
                    );

                    $message =
                        'Researcher affiliation updated successfully.';
                }
                else {

                    $dbh->do(
                        q{
                            INSERT INTO researcher_affiliations
                            (
                                borrowernumber,
                                organisation_name,
                                organisation_identifier,
                                department,
                                role_title,
                                start_date,
                                end_date,
                                is_current,
                                affiliation_type,
                                verification_status,
                                verified_by,
                                verified_at,
                                source,
                                created_at,
                                updated_at
                            )
                            VALUES
                            (
                                ?,
                                ?,
                                NULLIF(?, ''),
                                NULLIF(?, ''),
                                NULLIF(?, ''),
                                NULLIF(?, ''),
                                CASE
                                    WHEN ? = 1
                                    THEN NULL
                                    ELSE NULLIF(?, '')
                                END,
                                ?,
                                ?,
                                ?,
                                CASE
                                    WHEN ? = 'verified'
                                    THEN ?
                                    ELSE NULL
                                END,
                                CASE
                                    WHEN ? = 'verified'
                                    THEN NOW()
                                    ELSE NULL
                                END,
                                ?,
                                NOW(),
                                NOW()
                            )
                        },
                        undef,
                        $borrowernumber,
                        $affiliation_org,
                        $affiliation_org_id,
                        $affiliation_department,
                        $affiliation_role,
                        $affiliation_start,
                        $affiliation_current,
                        $affiliation_end,
                        $affiliation_current,
                        $affiliation_type,
                        $affiliation_status,
                        $affiliation_status,
                        $staff_borrowernumber || undef,
                        $affiliation_status,
                        $affiliation_source || 'staff-review'
                    );

                    audit_action(
                        borrowernumber => $borrowernumber,
                        action_type    => 'affiliation_added',
                        old_value      => '',
                        new_value      => join(
                            '; ',
                            'organisation=' . $affiliation_org,
                            'organisation_id=' . $affiliation_org_id,
                            'department=' . $affiliation_department,
                            'role=' . $affiliation_role,
                            'start=' . $affiliation_start,
                            'end=' . $affiliation_end,
                            'current=' . $affiliation_current,
                            'type=' . $affiliation_type,
                            'status=' . $affiliation_status,
                            'source=' . $affiliation_source
                        ),
                        reason => $reason
                            || 'Researcher affiliation added by staff',
                    );

                    $message =
                        'Researcher affiliation added successfully.';
                }

                if (
                       $affiliation_current
                    && $affiliation_type eq 'employment'
                ) {
                    $dbh->do(
                        q{
                            UPDATE custom_profile_details
                            SET
                                main_affiliation = ?,
                                department       = NULLIF(?, ''),
                                designation      = NULLIF(?, ''),
                                job_title        = NULLIF(?, ''),
                                working_group    = NULLIF(?, ''),
                                updated_at       = NOW()
                            WHERE borrowernumber = ?
                        },
                        undef,
                        $affiliation_org,
                        $affiliation_department,
                        $affiliation_role,
                        $affiliation_role,
                        $affiliation_department,
                        $borrowernumber
                    );
                }
            }
            elsif ($action eq 'save_identifier') {

                my $duplicate = $dbh->selectrow_array(
                    q{
                        SELECT id
                        FROM researcher_identifiers
                        WHERE identifier_type = ?
                          AND identifier_value = ?
                          AND borrowernumber <> ?
                        LIMIT 1
                    },
                    undef,
                    $identifier_type,
                    $identifier_value,
                    $borrowernumber
                );

                if ($duplicate) {
                    die
                        identifier_type_label($identifier_type)
                        . ' is already linked to another researcher.';
                }

                if ($identifier_primary) {
                    $dbh->do(
                        q{
                            UPDATE researcher_identifiers
                            SET
                                is_primary = 0,
                                updated_at = NOW()
                            WHERE borrowernumber = ?
                              AND identifier_type = ?
                        },
                        undef,
                        $borrowernumber,
                        $identifier_type
                    );
                }

                if ($identifier_id ne '') {

                    my $owned_identifier = $dbh->selectrow_hashref(
                        q{
                            SELECT
                                id AS identifier_id,
                                identifier_type,
                                identifier_value,
                                verification_status,
                                is_primary,
                                is_active,
                                verification_method AS verification_source
                            FROM researcher_identifiers
                            WHERE id = ?
                              AND borrowernumber = ?
                        },
                        undef,
                        $identifier_id,
                        $borrowernumber
                    );

                    if (!$owned_identifier) {
                        die 'Identifier record does not belong to this researcher.';
                    }

                    my $old_identifier_value = join(
                        '; ',
                        'type='
                            . ($owned_identifier->{identifier_type} // ''),
                        'value='
                            . ($owned_identifier->{identifier_value} // ''),
                        'status='
                            . ($owned_identifier->{verification_status} // ''),
                        'primary='
                            . ($owned_identifier->{is_primary} // 0),
                        'active='
                            . ($owned_identifier->{is_active} // 0),
                        'source='
                            . ($owned_identifier->{verification_source} // '')
                    );

                    $dbh->do(
                        q{
                            UPDATE researcher_identifiers
                            SET
                                identifier_type     = ?,
                                identifier_value    = ?,
                                verification_status = ?,
                                is_primary          = ?,
                                is_active           = ?,
                                verification_method = NULLIF(?, ''),
                                verified_at         =
                                    CASE
                                        WHEN ? = 'verified'
                                        THEN COALESCE(
                                            verified_at,
                                            NOW()
                                        )
                                        ELSE NULL
                                    END,
                                updated_at = NOW()
                            WHERE id = ?
                              AND borrowernumber = ?
                        },
                        undef,
                        $identifier_type,
                        $identifier_value,
                        $identifier_status,
                        $identifier_primary,
                        $identifier_active,
                        $identifier_source,
                        $identifier_status,
                        $identifier_id,
                        $borrowernumber
                    );


                    # RIMS_IDENTIFIER_CHANGE_LIFECYCLE_V1
                    #
                    # If a Scopus/WoS identifier value changes, quarantine
                    # links bound to the old source identity and remove
                    # old source-specific identity cache/name variants.
                    # Publication/master metadata is intentionally preserved.
                    my $old_identifier_type =
                        lc(
                            $owned_identifier->{identifier_type}
                            // ''
                        );

                    my $old_identifier_raw =
                        $owned_identifier->{identifier_value}
                        // '';

                    if (
                           $old_identifier_raw ne ''
                        && $old_identifier_raw ne $identifier_value
                        && (
                               $old_identifier_type eq 'scopus'
                            || $old_identifier_type eq 'wos'
                        )
                    ) {
                        my $old_source =
                            $old_identifier_type eq 'scopus'
                            ? 'scopus'
                            : 'wos';

                        $dbh->do(
                            q{
                                UPDATE researcher_publication_links
                                SET
                                    affiliation_status =
                                        'needs_review',
                                    match_score = 0.00,
                                    system_decision = 'review',
                                    review_status =
                                        'needs_review',
                                    reviewed_by = NULL,
                                    reviewed_at = NULL
                                WHERE borrowernumber = ?
                                  AND source_name = ?
                                  AND source_author_id = ?
                            },
                            undef,
                            $borrowernumber,
                            $old_source,
                            $old_identifier_raw
                        );

                        $dbh->do(
                            q{
                                DELETE
                                FROM researcher_author_identity_cache
                                WHERE borrowernumber = ?
                                  AND source_name = ?
                                  AND source_author_id = ?
                            },
                            undef,
                            $borrowernumber,
                            $old_source,
                            $old_identifier_raw
                        );

                        $dbh->do(
                            q{
                                DELETE
                                FROM researcher_source_name_variants
                                WHERE borrowernumber = ?
                                  AND source_name = ?
                                  AND source_author_id = ?
                            },
                            undef,
                            $borrowernumber,
                            $old_source,
                            $old_identifier_raw
                        );
                    }

                    audit_action(
                        borrowernumber => $borrowernumber,
                        action_type    => 'identifier_updated',
                        old_value      => $old_identifier_value,
                        new_value      => join(
                            '; ',
                            'type=' . $identifier_type,
                            'value=' . $identifier_value,
                            'status=' . $identifier_status,
                            'primary=' . $identifier_primary,
                            'active=' . $identifier_active,
                            'source=' . $identifier_source
                        ),
                        reason => $reason
                            || 'Researcher identifier updated by staff',
                    );

                    $message =
                        identifier_type_label($identifier_type)
                        . ' updated successfully.';
                }
                else {

                    my $same_type = $dbh->selectrow_array(
                        q{
                            SELECT id
                            FROM researcher_identifiers
                            WHERE borrowernumber = ?
                              AND identifier_type = ?
                              AND identifier_value = ?
                            LIMIT 1
                        },
                        undef,
                        $borrowernumber,
                        $identifier_type,
                        $identifier_value
                    );

                    if ($same_type) {
                        die 'This identifier is already present for the researcher.';
                    }

                    $dbh->do(
                        q{
                            INSERT INTO researcher_identifiers
                            (
                                borrowernumber,
                                identifier_type,
                                identifier_value,
                                verification_status,
                                is_primary,
                                is_active,
                                verification_method,
                                verified_at,
                                created_at,
                                updated_at
                            )
                            VALUES
                            (
                                ?,
                                ?,
                                ?,
                                ?,
                                ?,
                                ?,
                                NULLIF(?, ''),
                                CASE
                                    WHEN ? = 'verified'
                                    THEN NOW()
                                    ELSE NULL
                                END,
                                NOW(),
                                NOW()
                            )
                        },
                        undef,
                        $borrowernumber,
                        $identifier_type,
                        $identifier_value,
                        $identifier_status,
                        $identifier_primary,
                        $identifier_active,
                        $identifier_source,
                        $identifier_status
                    );

                    audit_action(
                        borrowernumber => $borrowernumber,
                        action_type    => 'identifier_added',
                        old_value      => '',
                        new_value      => join(
                            '; ',
                            'type=' . $identifier_type,
                            'value=' . $identifier_value,
                            'status=' . $identifier_status,
                            'primary=' . $identifier_primary,
                            'active=' . $identifier_active,
                            'source=' . $identifier_source
                        ),
                        reason => $reason
                            || 'Researcher identifier added by staff',
                    );

                    $message =
                        identifier_type_label($identifier_type)
                        . ' added successfully.';
                }

                # RIMS_IDENTIFIER_PUBLIC_PROFILE_SYNC_V1
                #
                # researcher_identifiers is the authoritative identifier
                # store. The public researcher directory/profile currently
                # consumes identifier columns from custom_profile_details.
                #
                # Therefore mirror only VERIFIED + PRIMARY + ACTIVE
                # identifiers into the public-profile columns.

                my $verified_identifiers =
                    $dbh->selectall_arrayref(
                        q{
                            SELECT
                                identifier_type,
                                identifier_value
                            FROM researcher_identifiers
                            WHERE borrowernumber = ?
                              AND verification_status = 'verified'
                              AND is_primary = 1
                              AND is_active = 1
                              AND identifier_type IN (
                                  'orcid',
                                  'scopus',
                                  'wos'
                              )
                        },
                        { Slice => {} },
                        $borrowernumber
                    );

                my %public_identifier = (
                    orcid  => undef,
                    scopus => undef,
                    wos    => undef,
                );

                for my $row (@{$verified_identifiers}) {
                    my $type = $row->{identifier_type} // '';

                    next if !exists $public_identifier{$type};

                    $public_identifier{$type} =
                        $row->{identifier_value};
                }

                $dbh->do(
                    q{
                        UPDATE custom_profile_details
                        SET
                            orcid            = ?,
                            scopus_author_id = ?,
                            researcher_id    = ?,
                            updated_at       = NOW()
                        WHERE borrowernumber = ?
                    },
                    undef,
                    $public_identifier{orcid},
                    $public_identifier{scopus},
                    $public_identifier{wos},
                    $borrowernumber
                );
            }
            elsif ($action eq 'save_profile') {

                my %allowed_user_types = map { $_ => 1 } (
                    'Faculty',
                    'PhD Scholar',
                    'Researcher',
                    'Staff',
                    'External Researcher',
                );

                if (
                       $user_type ne ''
                    && !$allowed_user_types{$user_type}
                ) {
                    die "Invalid researcher user type.";
                }

                my $effective_public = $public_input;
                my $effective_sync   = $sync_input;

                if ($employment_input eq 'former') {
                    $effective_public = 0;
                    $effective_sync   = 0;
                }

                if (
                       ($old->{verification_status} // '') ne 'verified'
                    && $effective_public
                ) {
                    $effective_public = 0;
                }

                $dbh->do(
                    q{
                        UPDATE custom_profile_details
                        SET
                            preferred_name    = ?,
                            official_name     = ?,
                            user_type         = NULLIF(?, ''),
                            department        = NULLIF(?, ''),
                            school            = NULLIF(?, ''),
                            designation       = NULLIF(?, ''),
                            employee_id       = NULLIF(?, ''),
                            joining_date      = NULLIF(?, ''),
                            employment_status = ?,
                            public_visibility = ?,
                            sync_enabled      = ?,

                            job_title         = NULLIF(?, ''),
                            working_group     = NULLIF(?, ''),

                            relieving_date =
                                CASE
                                    WHEN ? = 'active'
                                    THEN NULL
                                    ELSE COALESCE(
                                        relieving_date,
                                        CURDATE()
                                    )
                                END,

                            updated_at = NOW()
                        WHERE borrowernumber = ?
                    },
                    undef,
                    $preferred_name,
                    $official_name,
                    $user_type,
                    $department,
                    $school,
                    $designation,
                    $employee_id,
                    $joining_date,
                    $employment_input,
                    $effective_public,
                    $effective_sync,
                    $designation,
                    $department,
                    $employment_input,
                    $borrowernumber
                );

                if ($employment_input eq 'former') {
                    $dbh->do(
                        q{
                            UPDATE researcher_affiliations
                            SET
                                is_current = 0,
                                end_date   = COALESCE(
                                    end_date,
                                    CURDATE()
                                ),
                                updated_at = NOW()
                            WHERE borrowernumber = ?
                              AND is_current = 1
                        },
                        undef,
                        $borrowernumber
                    );
                }

                audit_action(
                    borrowernumber => $borrowernumber,
                    action_type    => 'profile_core_updated',
                    old_value      => $old_value,
                    new_value      => join(
                        '; ',
                        'preferred_name=' . $preferred_name,
                        'official_name=' . $official_name,
                        'user_type=' . $user_type,
                        'department=' . $department,
                        'school=' . $school,
                        'designation=' . $designation,
                        'employee_id=' . $employee_id,
                        'joining_date=' . $joining_date,
                        'employment_status=' . $employment_input,
                        'public_visibility=' . $effective_public,
                        'sync_enabled=' . $effective_sync
                    ),
                    reason => $reason
                        || 'Core researcher profile updated by staff',
                );

                $message = 'Researcher profile updated successfully.';
            }
            elsif ($action eq 'verify') {

                $dbh->do(
                    q{
                        UPDATE custom_profile_details
                        SET
                            profile_status       = 'approved',
                            verification_status  = 'verified',
                            public_visibility    =
                                CASE
                                    WHEN employment_status = 'active'
                                    THEN 1
                                    ELSE 0
                                END,
                            sync_enabled         =
                                CASE
                                    WHEN employment_status = 'active'
                                    THEN 1
                                    ELSE 0
                                END,
                            verified_by          = ?,
                            verified_at          = NOW(),
                            identity_decision    = 'verified',
                            status_reason        = ?,
                            updated_at           = NOW()
                        WHERE borrowernumber = ?
                    },
                    undef,
                    $staff_borrowernumber || undef,
                    $reason || 'Verified by library staff',
                    $borrowernumber
                );

                $dbh->do(
                    q{
                        UPDATE researcher_identifiers
                        SET
                            verification_status = 'verified',
                            verification_method = 'staff-review',
                            verified_by         = ?,
                            verified_at         = NOW(),
                            last_checked_at     = NOW()
                        WHERE borrowernumber = ?
                    },
                    undef,
                    $staff_borrowernumber || undef,
                    $borrowernumber
                );

                $dbh->do(
                    q{
                        UPDATE researcher_affiliations
                        SET
                            verification_status = 'verified',
                            verified_by         = ?,
                            verified_at         = NOW()
                        WHERE borrowernumber = ?
                          AND is_current = 1
                    },
                    undef,
                    $staff_borrowernumber || undef,
                    $borrowernumber
                );

                audit_action(
                    borrowernumber => $borrowernumber,
                    action_type    => 'profile_verified',
                    old_value      => $old_value,
                    new_value      =>
                        'profile_status=approved; '
                        . 'verification_status=verified',
                    reason         => $reason
                        || 'Verified by library staff',
                );

                # BU_AUTO_PUBLICATION_SYNC_V4
                #
                # Trigger borrower-specific publication harvesting after
                # successful verification. The borrower number is converted
                # to an integer before it is included in the background
                # command.
                if (
                    defined $borrowernumber
                    && $borrowernumber =~ /^\d+$/
                ) {
                    my $safe_borrowernumber =
                        int($borrowernumber);

                    my $sync_command =
                          'KOHA_CONF=/etc/koha/sites/INSTANCE/'
                        . 'koha-conf.xml '
                        . 'PERL5LIB=/usr/share/koha/lib '
                        . '/usr/bin/perl '
                        . '/usr/share/koha/bin/'
                        . 'bu-researcher-publication-sync.pl '
                        . 'INSTANCE '
                        . $safe_borrowernumber
                        . ' >> '
                        . '/var/log/koha/INSTANCE/'
                        . 'researcher-publication-sync-trigger.log '
                        . '2>&1 < /dev/null &';

                    system(
                        '/bin/sh',
                        '-c',
                        $sync_command
                    );
                }

                $message = 'Researcher profile verified successfully.';

                # BEGIN RIMS WOS AUTO SYNC V1
                # Start the WoS cache/API importer asynchronously after
                # successful staff verification. This does not delay the
                # browser response and does not expose the API key.
                if (
                       $borrowernumber
                    && $borrowernumber =~ /^\d+$/
                    && -x '/usr/share/koha/bin/bu-rims-wos-auto-sync.pl'
                ) {
                    my $sync_pid = fork();

                    if (
                        defined $sync_pid
                        && $sync_pid == 0
                    ) {
                        open STDIN,  '<', '/dev/null';
                        open STDOUT, '>>',
                            '/var/log/koha/INSTANCE/rims-wos-auto-sync.log';
                        open STDERR, '>&', STDOUT;

                        exec(
                            '/usr/bin/perl',
                            '/usr/share/koha/bin/bu-rims-wos-auto-sync.pl',
                            '--borrower',
                            $borrowernumber
                        );

                        exit 127;
                    }
                }
                # END RIMS WOS AUTO SYNC V1

            }
            elsif ($action eq 'reject') {

                $dbh->do(
                    q{
                        UPDATE custom_profile_details
                        SET
                            profile_status       = 'rejected',
                            verification_status  = 'rejected',
                            public_visibility    = 0,
                            sync_enabled         = 0,
                            verified_by          = ?,
                            verified_at          = NOW(),
                            identity_decision    = 'rejected',
                            status_reason        = ?,
                            updated_at           = NOW()
                        WHERE borrowernumber = ?
                    },
                    undef,
                    $staff_borrowernumber || undef,
                    $reason || 'Rejected by library staff',
                    $borrowernumber
                );

                $dbh->do(
                    q{
                        UPDATE researcher_identifiers
                        SET
                            verification_status = 'rejected',
                            verification_method = 'staff-review',
                            verified_by         = ?,
                            verified_at         = NOW(),
                            last_checked_at     = NOW()
                        WHERE borrowernumber = ?
                    },
                    undef,
                    $staff_borrowernumber || undef,
                    $borrowernumber
                );

                audit_action(
                    borrowernumber => $borrowernumber,
                    action_type    => 'profile_rejected',
                    old_value      => $old_value,
                    new_value      =>
                        'profile_status=rejected; '
                        . 'verification_status=rejected; '
                        . 'public_visibility=0',
                    reason         => $reason
                        || 'Rejected by library staff',
                );

                $message = 'Researcher profile rejected.';
            }
            elsif ($action eq 'hide_profile') {

                $dbh->do(
                    q{
                        UPDATE custom_profile_details
                        SET
                            public_visibility = 0,
                            sync_enabled      = 0,
                            profile_status    = 'hidden',
                            status_reason     = ?,
                            updated_at        = NOW()
                        WHERE borrowernumber = ?
                    },
                    undef,
                    $reason
                        || 'Researcher profile removed from public access by library staff',
                    $borrowernumber
                );

                audit_action(
                    borrowernumber => $borrowernumber,
                    action_type    => 'researcher_profile_hidden',
                    old_value      => $old_value,
                    new_value      =>
                        'profile_status=hidden; '
                        . 'public_visibility=0; '
                        . 'sync_enabled=0',
                    reason         => $reason
                        || 'Researcher profile removed from public access by library staff',
                );

                $message =
                    'Researcher profile removed from public access. '
                    . 'The Koha patron account and research data were retained.';
            }
            elsif ($action eq 'restore_profile') {

                # RESEARCHER_LIFECYCLE_FINAL_V7
                #
                # Restore means restore public access.
                # Employment status is determined automatically from the
                # current Koha patron expiry date.

                my $patron_lifecycle = $dbh->selectrow_hashref(
                    q{
                        SELECT
                            dateexpiry,
                            CASE
                                WHEN dateexpiry IS NOT NULL
                                 AND dateexpiry < CURDATE()
                                THEN 1
                                ELSE 0
                            END AS is_expired
                        FROM borrowers
                        WHERE borrowernumber = ?
                        LIMIT 1
                    },
                    undef,
                    $borrowernumber
                );

                die 'Koha patron account not found'
                    unless $patron_lifecycle;

                my $is_verified =
                    ($old->{verification_status} // '') eq 'verified'
                    ? 1
                    : 0;

                my $is_expired =
                    $patron_lifecycle->{is_expired}
                    ? 1
                    : 0;

                my $expiry_date =
                    $patron_lifecycle->{dateexpiry} // '';

                my $restore_employment =
                    $is_expired ? 'former' : 'active';

                my $restore_sync =
                    $is_expired ? 0 : 1;

                my $restore_visibility =
                    $is_verified ? 1 : 0;

                my $restore_profile_status =
                    $is_verified ? 'verified' : 'submitted';

                my $restore_reason;

                if ($is_expired) {
                    $restore_reason =
                        $reason
                        || (
                            'Researcher profile restored as Former because '
                            . 'patron card expired on '
                            . $expiry_date
                        );
                }
                else {
                    $restore_reason =
                        $reason
                        || 'Researcher profile restored as Active by library staff';
                }

                $dbh->do(
                    q{
                        UPDATE custom_profile_details
                        SET
                            employment_status = ?,
                            relieving_date =
                                CASE
                                    WHEN ? = 'former'
                                    THEN COALESCE(
                                        relieving_date,
                                        (
                                            SELECT dateexpiry
                                            FROM borrowers
                                            WHERE borrowers.borrowernumber =
                                                custom_profile_details.borrowernumber
                                        )
                                    )
                                    ELSE NULL
                                END,
                            profile_status = ?,
                            public_visibility = ?,
                            sync_enabled = ?,
                            status_reason = ?,
                            updated_at = NOW()
                        WHERE borrowernumber = ?
                    },
                    undef,
                    $restore_employment,
                    $restore_employment,
                    $restore_profile_status,
                    $restore_visibility,
                    $restore_sync,
                    $restore_reason,
                    $borrowernumber
                );

                audit_action(
                    borrowernumber => $borrowernumber,
                    action_type    =>
                        $is_expired
                        ? 'researcher_former_profile_restored'
                        : 'researcher_active_profile_restored',
                    old_value      => $old_value,
                    new_value      =>
                          'employment_status='
                        . $restore_employment
                        . '; public_visibility='
                        . $restore_visibility
                        . '; sync_enabled='
                        . $restore_sync
                        . '; patron_expiry='
                        . $expiry_date,
                    reason         => $restore_reason,
                );

                if (!$is_verified) {
                    $message =
                        'Researcher profile restored, but verification is required before public display.';
                }
                elsif ($is_expired) {
                    $message =
                        'Researcher profile restored as Former because the patron card is expired.';
                }
                else {
                    $message =
                        'Researcher profile restored as Active and made public.';
                }
            }
            elsif ($action eq 'delete_profile') {



                my $delete_profile =
                    $dbh->selectrow_hashref(
                        q{
                            SELECT
                                c.borrowernumber,
                                c.researcher_uuid,
                                c.preferred_name,
                                c.official_name,
                                c.orcid,
                                c.scopus_author_id,
                                c.researcher_id,
                                b.cardnumber
                            FROM custom_profile_details c
                            LEFT JOIN borrowers b
                              ON b.borrowernumber =
                                 c.borrowernumber
                            WHERE c.borrowernumber = ?
                            FOR UPDATE
                        },
                        undef,
                        $borrowernumber
                    ) || {};

                my $expected_name =
                       $delete_profile->{preferred_name}
                    || $delete_profile->{official_name}
                    || '';

                my $normalised_expected =
                    lc($expected_name // '');

                my $normalised_submitted =
                    lc($confirmation_name // '');

                for (
                    $normalised_expected,
                    $normalised_submitted
                ) {
                    s/^\s+|\s+$//g;
                    s/\s+/ /g;
                }

                die
                    'Researcher name confirmation does not match.'
                    if $normalised_expected eq ''
                    || $normalised_submitted ne
                       $normalised_expected;

                my $table_rows =
                    $dbh->selectall_arrayref(
                        q{
                            SELECT DISTINCT
                                c.table_name
                            FROM information_schema.columns c
                            JOIN information_schema.tables t
                              ON t.table_schema =
                                 c.table_schema
                             AND t.table_name =
                                 c.table_name
                            WHERE c.table_schema =
                                  DATABASE()
                              AND c.column_name =
                                  'borrowernumber'
                              AND c.table_name LIKE
                                  'researcher\_%'
                              AND c.table_name NOT LIKE
                                  '%\_bak\_%'
                              AND c.table_name NOT LIKE
                                  '%\_backup\_%'
                              AND c.table_name NOT IN (
                                  'researcher_profile_deletion_log'
                              )
                              AND t.table_type =
                                  'BASE TABLE'
                            ORDER BY c.table_name
                        },
                        { Slice => {} }
                    ) || [];

                my @delete_tables;

                for my $row (@{$table_rows}) {
                    my $table =
                        $row->{table_name} // '';

                    next
                        if $table eq ''
                        || $table !~ /\A[A-Za-z0-9_]+\z/;

                    push @delete_tables, $table;
                }

                my @count_report;

                for my $table (@delete_tables) {
                    my $quoted_table =
                        $dbh->quote_identifier($table);

                    my $count =
                        $dbh->selectrow_array(
                            "SELECT COUNT(*) "
                            . "FROM $quoted_table "
                            . "WHERE borrowernumber = ?",
                            undef,
                            $borrowernumber
                        ) || 0;

                    push @count_report,
                        $table . '=' . $count;
                }

                my $photo_count =
                    $dbh->selectrow_array(
                        q{
                            SELECT COUNT(*)
                            FROM patronimage
                            WHERE borrowernumber = ?
                        },
                        undef,
                        $borrowernumber
                    ) || 0;

                push @count_report,
                    'patronimage=' . $photo_count;

                $dbh->do(
                    q{
                        INSERT INTO
                            researcher_profile_deletion_log
                        (
                            deleted_borrowernumber,
                            researcher_uuid,
                            preferred_name,
                            official_name,
                            cardnumber,
                            orcid,
                            scopus_author_id,
                            researcher_id,
                            deleted_table_counts,
                            deletion_reason,
                            deleted_by,
                            patron_account_retained
                        )
                        VALUES (
                            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1
                        )
                    },
                    undef,
                    $borrowernumber,
                    $delete_profile->{researcher_uuid},
                    $delete_profile->{preferred_name},
                    $delete_profile->{official_name},
                    $delete_profile->{cardnumber},
                    $delete_profile->{orcid},
                    $delete_profile->{scopus_author_id},
                    $delete_profile->{researcher_id},
                    join('; ', @count_report),
                    $reason,
                    $staff_borrowernumber || undef
                );

                # The researcher photo belongs to the
                # researcher-profile layer, not the retained
                # Koha patron account.
                $dbh->do(
                    q{
                        DELETE FROM patronimage
                        WHERE borrowernumber = ?
                    },
                    undef,
                    $borrowernumber
                );

                # Delete researcher child records first.
                # The shared publication master is retained,
                # because it does not contain borrowernumber
                # and may be linked to other researchers.
                for my $table (@delete_tables) {
                    next
                        if $table eq
                           'custom_profile_details';

                    my $quoted_table =
                        $dbh->quote_identifier($table);

                    $dbh->do(
                        "DELETE FROM $quoted_table "
                        . "WHERE borrowernumber = ?",
                        undef,
                        $borrowernumber
                    );
                }

                # Parent researcher profile is deleted last.
                $dbh->do(
                    q{
                        DELETE FROM custom_profile_details
                        WHERE borrowernumber = ?
                    },
                    undef,
                    $borrowernumber
                );

                my $profile_still_exists =
                    $dbh->selectrow_array(
                        q{
                            SELECT COUNT(*)
                            FROM custom_profile_details
                            WHERE borrowernumber = ?
                        },
                        undef,
                        $borrowernumber
                    ) || 0;

                die
                    'Profile deletion verification failed.'
                    if $profile_still_exists;

                my $patron_still_exists =
                    $dbh->selectrow_array(
                        q{
                            SELECT COUNT(*)
                            FROM borrowers
                            WHERE borrowernumber = ?
                        },
                        undef,
                        $borrowernumber
                    ) || 0;

                die
                    'Koha patron account was unexpectedly missing.'
                    if !$patron_still_exists;

                $message =
                    'Researcher profile permanently deleted. '
                    . 'The Koha patron account was retained.';
            }
            elsif ($action eq 'mark_former') {

                $dbh->do(
                    q{
                        UPDATE custom_profile_details
                        SET
                            employment_status = 'former',
                            relieving_date    = COALESCE(
                                relieving_date,
                                CURDATE()
                            ),
                            public_visibility = 0,
                            sync_enabled      = 0,
                            status_reason     = ?,
                            updated_at        = NOW()
                        WHERE borrowernumber = ?
                    },
                    undef,
                    $reason || 'Marked former by library staff',
                    $borrowernumber
                );

                $dbh->do(
                    q{
                        UPDATE researcher_affiliations
                        SET
                            is_current = 0,
                            end_date   = COALESCE(
                                end_date,
                                CURDATE()
                            ),
                            updated_at = NOW()
                        WHERE borrowernumber = ?
                          AND is_current = 1
                    },
                    undef,
                    $borrowernumber
                );

                audit_action(
                    borrowernumber => $borrowernumber,
                    action_type    => 'researcher_marked_former',
                    old_value      => $old_value,
                    new_value      =>
                        'employment_status=former; '
                        . 'sync_enabled=0; '
                        . 'public_visibility=0',
                    reason         => $reason
                        || 'Marked former by library staff',
                );

                $message = 'Researcher marked as Former.';
            }
            elsif ($action eq 'reactivate') {

                $dbh->do(
                    q{
                        UPDATE custom_profile_details
                        SET
                            employment_status = 'active',
                            relieving_date    = NULL,
                            sync_enabled      = 1,
                            public_visibility =
                                CASE
                                    WHEN verification_status = 'verified'
                                    THEN 1
                                    ELSE 0
                                END,
                            status_reason     = ?,
                            updated_at        = NOW()
                        WHERE borrowernumber = ?
                    },
                    undef,
                    $reason || 'Reactivated by library staff',
                    $borrowernumber
                );

                $dbh->do(
                    q{
                        UPDATE researcher_affiliations
                        SET
                            is_current = 1,
                            end_date   = NULL,
                            updated_at = NOW()
                        WHERE id = (
                            SELECT affiliation_id
                            FROM (
                                SELECT MAX(id) AS affiliation_id
                                FROM researcher_affiliations
                                WHERE borrowernumber = ?
                            ) latest_affiliation
                        )
                    },
                    undef,
                    $borrowernumber
                );

                audit_action(
                    borrowernumber => $borrowernumber,
                    action_type    => 'researcher_reactivated',
                    old_value      => $old_value,
                    new_value      =>
                        'employment_status=active; sync_enabled=1',
                    reason         => $reason
                        || 'Reactivated by library staff',
                );

                $message = 'Researcher reactivated successfully.';
            }

            $dbh->commit;
            $dbh->{AutoCommit} = 1;
        };

        if ($@) {
            my $failure = $@;

            eval { $dbh->rollback };
            $dbh->{AutoCommit} = 1;

            $error = 'Action failed: ' . $failure;
        }
    }
}


my $edit_borrowernumber =
       param_text('edit')
    || (
           $query->request_method eq 'POST'
        ? param_text('borrowernumber')
        : ''
    );
my $edit_profile;

if (
       valid_borrowernumber($edit_borrowernumber)
    && profile_exists($edit_borrowernumber)
) {
    $edit_profile = $dbh->selectrow_hashref(
        q{
            SELECT
                c.borrowernumber,
                c.researcher_uuid,
                c.preferred_name,
                c.official_name,
                c.user_type,
                c.department,
                c.school,
                c.designation,
                c.employee_id,
                c.joining_date,
                c.relieving_date,
                c.employment_status,
                c.public_visibility,
                c.sync_enabled,
                c.verification_status,
                c.profile_status,
                c.updated_at,
                b.cardnumber,
                b.surname,
                b.firstname,
                b.email
            FROM custom_profile_details c
            JOIN borrowers b
              ON b.borrowernumber = c.borrowernumber
            WHERE c.borrowernumber = ?
        },
        undef,
        $edit_borrowernumber
    );
}


my $edit_identifiers = [];

if ($edit_profile) {
    $edit_identifiers = $dbh->selectall_arrayref(
        q{
            SELECT
                id AS identifier_id,
                identifier_type,
                identifier_value,
                verification_status,
                is_primary,
                is_active,
                verification_method AS verification_source,
                verified_at,
                created_at,
                updated_at
            FROM researcher_identifiers
            WHERE borrowernumber = ?
            ORDER BY
                CASE identifier_type
                    WHEN 'orcid' THEN 1
                    WHEN 'scopus' THEN 2
                    WHEN 'wos' THEN 3
                    WHEN 'google_scholar' THEN 4
                    ELSE 5
                END,
                is_primary DESC,
                id
        },
        { Slice => {} },
        $edit_borrowernumber
    );
}


my $edit_affiliations = [];

if ($edit_profile) {
    $edit_affiliations = $dbh->selectall_arrayref(
        q{
            SELECT
                id AS affiliation_id,
                organisation_name,
                organisation_identifier,
                department,
                role_title,
                start_date,
                end_date,
                is_current,
                affiliation_type,
                verification_status,
                verified_by,
                verified_at,
                source,
                created_at,
                updated_at
            FROM researcher_affiliations
            WHERE borrowernumber = ?
            ORDER BY
                is_current DESC,
                COALESCE(end_date, '9999-12-31') DESC,
                COALESCE(start_date, '0001-01-01') DESC,
                id DESC
        },
        { Slice => {} },
        $edit_borrowernumber
    ) || [];
}

my $edit_name_variants = [];

if ($edit_profile) {
    $edit_name_variants = $dbh->selectall_arrayref(
        q{
            SELECT
                id AS variant_id,
                name_variant,
                normalised_variant,
                source,
                is_verified,
                verified_by,
                verified_at,
                created_at,
                updated_at
            FROM researcher_name_variants
            WHERE borrowernumber = ?
            ORDER BY is_verified DESC, name_variant ASC, id ASC
        },
        { Slice => {} },
        $edit_borrowernumber
    ) || [];
}

my $summary = $dbh->selectrow_hashref(
    q{
        SELECT
            COUNT(*) AS total_profiles,

            SUM(
                CASE
                    WHEN verification_status = 'pending'
                    THEN 1 ELSE 0
                END
            ) AS pending_profiles,

            SUM(
                CASE
                    WHEN verification_status = 'verified'
                    THEN 1 ELSE 0
                END
            ) AS verified_profiles,

            SUM(
                CASE
                    WHEN verification_status = 'rejected'
                    THEN 1 ELSE 0
                END
            ) AS rejected_profiles,

            SUM(
                CASE
                    WHEN employment_status = 'active'
                    THEN 1 ELSE 0
                END
            ) AS active_profiles,

            SUM(
                CASE
                    WHEN employment_status = 'former'
                    THEN 1 ELSE 0
                END
            ) AS former_profiles,

            SUM(
                CASE
                    WHEN employment_status = 'active'
                     AND verification_status = 'verified'
                    THEN 1 ELSE 0
                END
            ) AS current_verified_researchers,

            SUM(
                CASE
                    WHEN employment_status = 'active'
                     AND verification_status = 'verified'
                     AND EXISTS (
                         SELECT 1
                         FROM researcher_publication_links rpl
                         WHERE rpl.borrowernumber =
                               custom_profile_details.borrowernumber
                           AND rpl.source_name = 'scopus'
                           AND rpl.system_decision = 'confirmed'
                     )
                    THEN 1 ELSE 0
                END
            ) AS current_scopus_authors,

            SUM(
                CASE
                    WHEN employment_status = 'active'
                     AND verification_status = 'verified'
                     AND COALESCE(researcher_id, '') <> ''
                    THEN 1 ELSE 0
                END
            ) AS current_wos_authors,

            SUM(
                CASE
                    WHEN employment_status = 'active'
                     AND verification_status = 'verified'
                     AND COALESCE(orcid, '') <> ''
                    THEN 1 ELSE 0
                END
            ) AS current_orcid_researchers

        FROM custom_profile_details
    }
) || {};

my $status_filter = param_text('status');
my $type_filter   = param_text('user_type');
my $search        = param_text('q');

my @where;
my @bind;

if ($status_filter eq 'pending') {
    push @where, q{c.verification_status = 'pending'};
}
elsif ($status_filter eq 'verified') {
    push @where, q{c.verification_status = 'verified'};
}
elsif ($status_filter eq 'rejected') {
    push @where, q{c.verification_status = 'rejected'};
}
elsif ($status_filter eq 'active') {
    push @where, q{c.employment_status = 'active'};
}
elsif ($status_filter eq 'former') {
    push @where, q{c.employment_status = 'former'};
}

if ($type_filter ne '') {
    push @where, q{c.user_type = ?};
    push @bind, $type_filter;
}

if ($search ne '') {
    my $like = '%' . $search . '%';

    push @where, q{
        (
            c.preferred_name LIKE ?
            OR c.official_name LIKE ?
            OR c.employee_id LIKE ?
            OR c.orcid LIKE ?
            OR c.scopus_author_id LIKE ?
            OR c.researcher_id LIKE ?
            OR c.working_group LIKE ?
        )
    };

    push @bind, ($like) x 7;
}

my $where_sql = @where
    ? 'WHERE ' . join(' AND ', @where)
    : '';

my $profiles = $dbh->selectall_arrayref(
    qq{
        SELECT
            c.borrowernumber,
            c.preferred_name,
            c.official_name,
            c.user_type,
            c.department,
            c.school,
            c.designation,
            c.joining_date,
            c.researcher_uuid,
            c.job_title,
            c.main_affiliation,
            c.working_group,
            c.employee_id,
            c.orcid,
            c.scopus_author_id,
            c.researcher_id,
            c.profile_status,
            c.verification_status,
            c.employment_status,
            c.public_visibility,
            c.sync_enabled,
            c.verified_at,
            c.relieving_date,
            c.status_reason,
            c.updated_at,
            b.cardnumber,
            b.categorycode,
            b.dateexpiry
        FROM custom_profile_details c
        JOIN borrowers b
          ON b.borrowernumber = c.borrowernumber
        $where_sql
        ORDER BY
            CASE c.verification_status
                WHEN 'pending' THEN 1
                WHEN 'verified' THEN 2
                WHEN 'rejected' THEN 3
                ELSE 4
            END,
            c.updated_at DESC,
            c.preferred_name ASC
        LIMIT 500
    },
    { Slice => {} },
    @bind
) || [];

my $audit_rows = $dbh->selectall_arrayref(
    q{
        SELECT
            l.id,
            l.borrowernumber,
            l.action_type,
            l.action_reason,
            l.performed_by,
            l.source,
            l.created_at,
            c.preferred_name
        FROM researcher_audit_log l
        LEFT JOIN custom_profile_details c
          ON c.borrowernumber = l.borrowernumber
        ORDER BY l.id DESC
        LIMIT 50
    },
    { Slice => {} }
) || [];

my @user_types = (
    'Faculty',
    'PhD Scholar',
    'Researcher',
    'Staff',
    'External Researcher',
);

$template->param(
    message       => $message,
    error         => $error,
    summary       => $summary,
    profiles      => $profiles,
    audit_rows    => $audit_rows,
    status_filter => $status_filter,
    type_filter   => $type_filter,
    q             => $search,
    user_types    => \@user_types,
    profile_url   => $PROFILE_URL,
    csrf_token   => $csrf_token,
    edit_profile      => $edit_profile,
    edit_identifiers    => $edit_identifiers,
    edit_affiliations   => $edit_affiliations,
    edit_name_variants  => $edit_name_variants,
);

output_html_with_http_headers(
    $query,
    $cookie,
    $template->output
);
