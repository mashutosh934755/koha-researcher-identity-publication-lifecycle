#!/usr/bin/perl

use Modern::Perl;
use Try::Tiny;

use C4::Context;
use C4::Letters;

my $dbh = C4::Context->dbh;

# BEGIN RESEARCHER V2 ONBOARDING
#
# Returning researchers must be detected before a new scholarly
# identity/profile is created.
#
my $rejoin_detector =
    '/usr/share/koha/bin/bu-researcher-rejoin-detect.pl';
# END RESEARCHER V2 ONBOARDING

my %type_map = (
    FACULTY     => 'Faculty',
    PHD_SCHOLAR => 'PhD Scholar',
    RESEARCHER  => 'Researcher',
    STAFF       => 'Staff',
    EXTERNAL    => 'External Researcher',
);

my $sth = $dbh->prepare(q{
    SELECT
        b.borrowernumber,
        b.firstname,
        b.surname,
        b.email,
        ba.attribute AS researcher_type_code
    FROM borrowers b
    INNER JOIN borrower_attributes ba
        ON ba.borrowernumber=b.borrowernumber
       AND ba.code='RESTYPE'
    LEFT JOIN researcher_onboarding_log rol
        ON rol.borrowernumber=b.borrowernumber
    WHERE ba.attribute IN
    (
        'FACULTY',
        'PHD_SCHOLAR',
        'RESEARCHER',
        'STAFF',
        'EXTERNAL'
    )
      AND rol.borrowernumber IS NULL
    ORDER BY b.borrowernumber
});

$sth->execute;

my $processed = 0;

while (my $row = $sth->fetchrow_hashref) {

    my $borrowernumber = $row->{borrowernumber};

    my $researcher_type =
        $type_map{$row->{researcher_type_code}}
        || $row->{researcher_type_code};

    try {

        # ====================================================
        # BEGIN RETURNING RESEARCHER GATE V2
        # ====================================================

        # A borrower already attached to a permanent identity
        # must never receive another researcher UUID.
        my $existing_identity =
            $dbh->selectrow_array(
                q{
                    SELECT researcher_uuid
                    FROM researcher_patron_links
                    WHERE borrowernumber = ?
                    LIMIT 1
                },
                undef,
                $borrowernumber
            );

        if ($existing_identity) {

            say join(
                ' | ',
                "borrowernumber=$borrowernumber",
                "type=$researcher_type",
                "status=already_identity_linked",
                "researcher_uuid=$existing_identity",
            );

            next;
        }


        # Run returning-researcher detection BEFORE creating
        # custom_profile_details / UUID.
        #
        # --apply here does NOT reconnect identities.
        # It only stores a pending librarian-review candidate.
        #
        if (-x $rejoin_detector) {

            my $detector_rc =
                system(
                    $rejoin_detector,
                    '--borrower',
                    $borrowernumber,
                    '--apply'
                );

            if ($detector_rc == -1) {

                warn
                    "Could not execute rejoin detector "
                    . "for borrower $borrowernumber: $!\n";

            }
            elsif ($detector_rc & 127) {

                warn
                    "Rejoin detector terminated abnormally "
                    . "for borrower $borrowernumber\n";
            }
        }


        # Was a pending rejoin case created?
        my $rejoin_candidate =
            $dbh->selectrow_hashref(
                q{
                    SELECT
                        id,
                        candidate_researcher_uuid,
                        confidence_score
                    FROM researcher_rejoin_candidates
                    WHERE new_borrowernumber = ?
                      AND review_status = 'pending'
                    ORDER BY
                        confidence_score DESC,
                        id DESC
                    LIMIT 1
                },
                undef,
                $borrowernumber
            );


        my $stop_normal_onboarding = 0;

        if ($rejoin_candidate) {

            # Mark onboarding as handled so the 10-minute cron
            # does not repeatedly create/re-run the same review.
            $dbh->do(
                q{
                    INSERT INTO researcher_onboarding_log
                    (
                        borrowernumber,
                        researcher_type,
                        email_address,
                        message_id,
                        status,
                        queued_at,
                        last_error
                    )
                    VALUES
                    (
                        ?, ?, ?, NULL,
                        'rejoin_review',
                        NOW(),
                        NULL
                    )
                },
                undef,
                $borrowernumber,
                $researcher_type,
                $row->{email}
            );

            say join(
                ' | ',
                "borrowernumber=$borrowernumber",
                "type=$researcher_type",
                "status=rejoin_review",
                "candidate_id="
                    . $rejoin_candidate->{id},
                "candidate_uuid="
                    . $rejoin_candidate->{candidate_researcher_uuid},
                "confidence="
                    . ($rejoin_candidate->{confidence_score} // ''),
            );

            # Do not leave the try{} block with Perl 'next'.
            # Instead use an explicit control flag.
            $stop_normal_onboarding = 1;
        }

        # ====================================================
        # END RETURNING RESEARCHER GATE V2
        # ====================================================

        if (!$stop_normal_onboarding) {

        $dbh->do(
            q{
                INSERT INTO custom_profile_details
                (
                    borrowernumber,
                    researcher_uuid,
                    first_name,
                    last_name,
                    email,
                    user_type,
                    profile_status,
                    verification_status,
                    employment_status,
                    sync_enabled,
                    public_visibility,
                    created_at,
                    updated_at
                )
                VALUES
                (
                    ?,
                    UUID(),
                    ?,
                    ?,
                    ?,
                    ?,
                    'draft',
                    'pending',
                    'active',
                    1,
                    0,
                    NOW(),
                    NOW()
                )
                ON DUPLICATE KEY UPDATE
                    first_name =
                        COALESCE(NULLIF(first_name,''), VALUES(first_name)),

                    last_name =
                        COALESCE(NULLIF(last_name,''), VALUES(last_name)),

                    email =
                        COALESCE(NULLIF(email,''), VALUES(email)),

                    user_type =
                        CASE
                            WHEN user_type IS NULL OR user_type=''
                                THEN VALUES(user_type)
                            ELSE user_type
                        END,

                    updated_at=NOW()
            },
            undef,
            $borrowernumber,
            $row->{firstname},
            $row->{surname},
            $row->{email},
            $researcher_type
        );

        # ====================================================
        # BEGIN NORMAL NEW-RESEARCHER V2 REGISTRATION
        # ====================================================

        my $new_profile =
            $dbh->selectrow_hashref(
                q{
                    SELECT
                        researcher_uuid,
                        borrowernumber,
                        first_name,
                        last_name,
                        email,
                        verification_status,
                        employment_status,
                        employee_id,
                        department,
                        designation,
                        joining_date
                    FROM custom_profile_details
                    WHERE borrowernumber = ?
                    LIMIT 1
                },
                undef,
                $borrowernumber
            );

        die
            "New researcher profile exists without researcher_uuid"
            unless
                $new_profile
                && $new_profile->{researcher_uuid};


        my $canonical_name =
            join(
                ' ',
                grep {
                    defined($_)
                    && $_ ne ''
                }
                (
                    $new_profile->{first_name},
                    $new_profile->{last_name}
                )
            );

        $canonical_name ||=
            join(
                ' ',
                grep {
                    defined($_)
                    && $_ ne ''
                }
                (
                    $row->{firstname},
                    $row->{surname}
                )
            );

        $canonical_name ||=
            "Researcher $borrowernumber";


        # Permanent scholarly person.
        $dbh->do(
            q{
                INSERT INTO researcher_persons
                (
                    researcher_uuid,
                    canonical_name,
                    lifecycle_status,
                    verification_status,
                    created_at,
                    updated_at
                )
                VALUES
                (
                    ?,
                    ?,
                    'current',
                    ?,
                    NOW(),
                    NOW()
                )

                ON DUPLICATE KEY UPDATE
                    canonical_name =
                        COALESCE(
                            NULLIF(canonical_name,''),
                            VALUES(canonical_name)
                        ),
                    updated_at=NOW()
            },
            undef,
            $new_profile->{researcher_uuid},
            $canonical_name,
            (
                $new_profile->{verification_status}
                || 'pending'
            )
        );


        # Koha account -> permanent scholarly person.
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

                SELECT
                    ?,
                    b.borrowernumber,
                    b.cardnumber,
                    NULLIF(?, ''),
                    COALESCE(
                        NULLIF(?, ''),
                        NULLIF(b.email,'')
                    ),
                    'current',
                    COALESCE(
                        ?,
                        b.dateenrolled
                    ),
                    NULL,
                    'automatic_onboarding_v2',
                    100.00,
                    NOW(),
                    NOW()

                FROM borrowers b
                WHERE b.borrowernumber = ?

                ON DUPLICATE KEY UPDATE
                    researcher_uuid =
                        VALUES(researcher_uuid),
                    cardnumber =
                        VALUES(cardnumber),
                    employee_id =
                        COALESCE(
                            NULLIF(employee_id,''),
                            VALUES(employee_id)
                        ),
                    institutional_email =
                        COALESCE(
                            NULLIF(institutional_email,''),
                            VALUES(institutional_email)
                        ),
                    link_status='current',
                    valid_to=NULL,
                    updated_at=NOW()
            },
            undef,
            $new_profile->{researcher_uuid},
            ($new_profile->{employee_id} // ''),
            ($new_profile->{email} // ''),
            $new_profile->{joining_date},
            $borrowernumber
        );


        # Initial employment episode.
        my $episode_exists =
            $dbh->selectrow_array(
                q{
                    SELECT COUNT(*)
                    FROM researcher_employment_episodes
                    WHERE researcher_uuid = ?
                      AND borrowernumber = ?
                },
                undef,
                $new_profile->{researcher_uuid},
                $borrowernumber
            );

        if (!$episode_exists) {

            my $dateenrolled =
                $dbh->selectrow_array(
                    q{
                        SELECT dateenrolled
                        FROM borrowers
                        WHERE borrowernumber = ?
                    },
                    undef,
                    $borrowernumber
                );

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
                    VALUES
                    (
                        ?,
                        ?,
                        'Example University',
                        ?,
                        ?,
                        ?,
                        ?,
                        NULL,
                        'current',
                        'automatic-onboarding-v2',
                        NOW(),
                        NOW()
                    )
                },
                undef,
                $new_profile->{researcher_uuid},
                $borrowernumber,
                ($new_profile->{employee_id} // undef),
                ($new_profile->{department} // undef),
                ($new_profile->{designation} // undef),
                (
                    $new_profile->{joining_date}
                    || $dateenrolled
                )
            );
        }

        # ====================================================
        # END NORMAL NEW-RESEARCHER V2 REGISTRATION
        # ====================================================


        my $message_id;
        my $status;

        my $existing_message = $dbh->selectrow_array(
            q{
                SELECT message_id
                FROM message_queue
                WHERE borrowernumber=?
                  AND subject=
                    'Welcome to Example University Researcher Identity System'
                  AND status IN ('pending','sent')
                ORDER BY message_id DESC
                LIMIT 1
            },
            undef,
            $borrowernumber
        );

        if ($existing_message) {
            $message_id = $existing_message;
            $status = 'already_sent';
        }
        elsif (!$row->{email} || $row->{email} !~ /\@/) {
            $status = 'no_email';
        }
        else {
            my $letter = C4::Letters::GetPreparedLetter(
                module      => 'members',
                letter_code => 'RESEARCHER_WELCOME',
                branchcode  => '',
                lang        => 'default',
                tables      => {
                    borrowers => $borrowernumber,
                },
            );

            die "RESEARCHER_WELCOME notice preparation failed"
                unless $letter;

            $message_id = C4::Letters::EnqueueLetter({
                borrowernumber         => $borrowernumber,
                letter                 => $letter,
                message_transport_type => 'email',
                to_address             => $row->{email},
            });

            die "Welcome email could not be queued"
                unless $message_id;

            $status = 'queued';
        }

        $dbh->do(
            q{
                INSERT INTO researcher_onboarding_log
                (
                    borrowernumber,
                    researcher_type,
                    email_address,
                    message_id,
                    status,
                    queued_at,
                    last_error
                )
                VALUES
                (
                    ?, ?, ?, ?, ?, NOW(), NULL
                )
            },
            undef,
            $borrowernumber,
            $researcher_type,
            $row->{email},
            $message_id,
            $status
        );

        $processed++;

        say join(
            ' | ',
            "borrowernumber=$borrowernumber",
            "type=$researcher_type",
            "status=$status",
            "message_id=" . ($message_id // ''),
        );

        } # end normal onboarding path
    }
    catch {
        my $error = $_ || 'Unknown onboarding error';

        warn "ERROR borrower $borrowernumber: $error\n";
    };
}

say "ONBOARDING_COMPLETE processed=$processed";

exit 0;
