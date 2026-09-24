#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use C4::Context;
use Encode qw(decode encode);
use Getopt::Long qw(GetOptions);
use HTTP::Request;
use JSON::MaybeXS qw(decode_json encode_json);
use LWP::UserAgent;
use URI::Escape qw(uri_escape_utf8);

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $instance       = $ENV{KOHA_INSTANCE} || 'INSTANCE';
my $borrowernumber = 0;
my $all            = 0;

GetOptions(
    'instance=s'       => \$instance,
    'borrowernumber=i' => \$borrowernumber,
    'all'              => \$all,
) or die "Invalid command options\n";

die "Use --borrowernumber=NUMBER or --all\n"
    unless $borrowernumber || $all;

my $dbh = C4::Context->dbh;

my $env_file =
    "/etc/koha/sites/$instance/research-api.env";

sub trim {
    my ($value) = @_;

    return '' unless defined $value;
    return '' if ref $value;

    $value = "$value";
    $value =~ s/[\x{0000}-\x{001F}\x{007F}]+/ /g;
    $value =~ s/\s+/ /g;
    $value =~ s/^\s+|\s+$//g;

    return $value;
}

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
            /^\s*([A-Z][A-Z0-9_]*)\s*=\s*"(.*)"\s*$/
        ) {
            $env{$1} = $2;
        }
        elsif (
            $line =~
            /^\s*([A-Z][A-Z0-9_]*)\s*=\s*'(.*)'\s*$/
        ) {
            $env{$1} = $2;
        }
        elsif (
            $line =~
            /^\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*?)\s*$/
        ) {
            $env{$1} = $2;
        }
    }

    close $fh;

    return %env;
}

my %env = read_env_file($env_file);

my $scopus_api_key =
    trim($env{SCOPUS_API_KEY});

my $wos_api_key =
    trim($env{WOS_API_KEY});

my $wos_db =
    trim($env{WOS_DB}) || 'WOS';

die "SCOPUS_API_KEY missing\n"
    if $scopus_api_key eq '';

die "WOS_API_KEY missing\n"
    if $wos_api_key eq '';

my $ua = LWP::UserAgent->new(
    timeout => 90,
);

$ua->agent(
    'Koha-RIMS-Official-Author-Names/1.0'
);

sub normalise_identifier {
    my ($value) = @_;

    $value = lc trim($value);
    $value =~ s{^https?://orcid\.org/}{};
    $value =~ s/[^a-z0-9]//g;

    return $value;
}

sub normalise_name {
    my ($value) = @_;

    $value = lc trim($value);
    $value =~ s/\b(?:dr|prof|professor)\b//g;
    $value =~ s/[^a-z0-9]+/ /g;
    $value =~ s/\s+/ /g;
    $value =~ s/^\s+|\s+$//g;

    return $value;
}

sub valid_person_name {
    my ($value) = @_;

    $value = trim($value);

    return 0 if $value eq '';
    return 0 if length($value) < 2;
    return 0 if length($value) > 250;
    return 0 if $value =~ m{https?://}i;
    return 0 if $value =~ /\#/;
    return 0 if $value =~ /^\d+$/;

    return 1;
}

sub get_json {
    my (%args) = @_;

    my $request =
        HTTP::Request->new(
            GET => $args{url}
        );

    $request->header(
        'Accept' => 'application/json'
    );

    if ($args{source} eq 'scopus') {
        $request->header(
            'X-ELS-APIKey' => $scopus_api_key
        );
    }
    elsif ($args{source} eq 'wos') {
        $request->header(
            'X-ApiKey' => $wos_api_key
        );
    }

    my $response =
        $ua->request($request);

    die sprintf(
        "%s API HTTP %s: %s\n",
        uc($args{source}),
        $response->code,
        substr(
            trim($response->decoded_content),
            0,
            1000
        )
    ) unless $response->is_success;

    my $payload;

    eval {
        $payload =
            decode_json(
                $response->decoded_content
            );
    };

    die sprintf(
        "%s API invalid JSON\n",
        uc($args{source})
    ) if $@ || !defined $payload;

    return $payload;
}

sub source_profile_url {
    my ($source, $author_id) = @_;

    if ($source eq 'scopus') {
        return
            'https://www.scopus.com/authid/detail.uri?authorId='
            . uri_escape_utf8($author_id);
    }

    return
        'https://www.webofscience.com/wos/author/record/'
        . uri_escape_utf8($author_id);
}

sub save_identity_cache {
    my (%args) = @_;

    my $exists =
        $dbh->selectrow_array(
            q{
                SELECT COUNT(*)
                FROM researcher_author_identity_cache
                WHERE borrowernumber = ?
                  AND source_name = ?
                  AND source_author_id = ?
            },
            undef,
            $args{borrowernumber},
            $args{source},
            $args{author_id}
        ) || 0;

    if ($exists) {
        $dbh->do(
            q{
                UPDATE researcher_author_identity_cache
                SET
                    display_name = ?,
                    published_name = ?,
                    raw_json = ?,
                    extraction_method = ?,
                    profile_url = ?,
                    last_fetched_at = NOW()
                WHERE borrowernumber = ?
                  AND source_name = ?
                  AND source_author_id = ?
            },
            undef,
            $args{display_name},
            $args{published_name},
            $args{raw_json},
            $args{method},
            $args{profile_url},
            $args{borrowernumber},
            $args{source},
            $args{author_id}
        );
    }
    else {
        $dbh->do(
            q{
                INSERT INTO researcher_author_identity_cache
                (
                    borrowernumber,
                    source_name,
                    source_author_id,
                    display_name,
                    published_name,
                    raw_json,
                    extraction_method,
                    profile_url,
                    first_fetched_at,
                    last_fetched_at
                )
                VALUES
                (
                    ?, ?, ?, ?, ?, ?, ?, ?,
                    NOW(), NOW()
                )
            },
            undef,
            $args{borrowernumber},
            $args{source},
            $args{author_id},
            $args{display_name},
            $args{published_name},
            $args{raw_json},
            $args{method},
            $args{profile_url}
        );
    }
}

sub save_variant {
    my (%args) = @_;

    my $name = trim($args{name});

    return 0 unless valid_person_name($name);

    my $exists =
        $dbh->selectrow_array(
            q{
                SELECT COUNT(*)
                FROM researcher_source_name_variants
                WHERE borrowernumber = ?
                  AND source_name = ?
                  AND source_author_id = ?
                  AND name_value = ?
            },
            undef,
            $args{borrowernumber},
            $args{source},
            $args{author_id},
            $name
        ) || 0;

    if ($exists) {
        $dbh->do(
            q{
                UPDATE researcher_source_name_variants
                SET
                    name_type = ?,
                    api_json_path = ?,
                    extraction_method = ?,
                    is_primary =
                        GREATEST(is_primary, ?),
                    profile_url = ?,
                    last_fetched_at = NOW()
                WHERE borrowernumber = ?
                  AND source_name = ?
                  AND source_author_id = ?
                  AND name_value = ?
            },
            undef,
            $args{name_type},
            $args{json_path},
            $args{method},
            $args{is_primary} ? 1 : 0,
            $args{profile_url},
            $args{borrowernumber},
            $args{source},
            $args{author_id},
            $name
        );
    }
    else {
        $dbh->do(
            q{
                INSERT INTO researcher_source_name_variants
                (
                    borrowernumber,
                    source_name,
                    source_author_id,
                    name_type,
                    name_value,
                    api_json_path,
                    extraction_method,
                    is_primary,
                    profile_url,
                    first_fetched_at,
                    last_fetched_at
                )
                VALUES
                (
                    ?, ?, ?, ?, ?, ?, ?, ?, ?,
                    NOW(), NOW()
                )
            },
            undef,
            $args{borrowernumber},
            $args{source},
            $args{author_id},
            $args{name_type},
            $name,
            $args{json_path},
            $args{method},
            $args{is_primary} ? 1 : 0,
            $args{profile_url}
        );
    }

    return 1;
}

sub object_identifier_values {
    my ($object) = @_;

    return () unless ref($object) eq 'HASH';

    my @values;

    for my $key (
        '@auid',
        'auid',
        'authid',
        'authorId',
        'author-id',
        'researcherId',
        'researcherID',
        'researcher-id',
        'rid',
        'orcid',
        'orcidId',
        'orcid-id'
    ) {
        next unless exists $object->{$key};

        my $value =
            $object->{$key};

        if (ref($value) eq 'ARRAY') {
            push @values, @{$value};
        }
        elsif (ref($value) eq 'HASH') {
            push @values, values %{$value};
        }
        elsif (defined $value) {
            push @values, $value;
        }
    }

    return grep {
        defined $_ && !ref($_)
    } @values;
}

sub identifier_matches {
    my (%args) = @_;

    my %wanted =
        map {
            normalise_identifier($_) => 1
        }
        grep {
            trim($_) ne ''
        }
        @{$args{identifiers} || []};

    return 0 unless keys %wanted;

    for my $value (
        object_identifier_values(
            $args{object}
        )
    ) {
        my $normalised =
            normalise_identifier($value);

        return 1 if
            $normalised ne ''
            && $wanted{$normalised};
    }

    return 0;
}

sub scopus_author_object_name {
    my ($object) = @_;

    return '' unless ref($object) eq 'HASH';

    for my $key (
        'authname',
        'ce:indexed-name',
        'indexed-name',
        'display-name',
        'displayName',
        'full-name',
        'fullName'
    ) {
        my $value = trim($object->{$key});

        return $value
            if valid_person_name($value);
    }

    my $given = trim(
           $object->{'given-name'}
        || $object->{'ce:given-name'}
        || $object->{givenName}
    );

    my $surname = trim(
           $object->{surname}
        || $object->{'ce:surname'}
        || $object->{familyName}
    );

    if ($given ne '' && $surname ne '') {
        return "$surname, $given";
    }

    return '';
}

sub update_publication_author_name {
    my (%args) = @_;

    return unless valid_person_name(
        $args{name}
    );

    return if trim($args{record_id}) eq '';

    $dbh->do(
        q{
            UPDATE researcher_publication_links rpl
            INNER JOIN researcher_publication_sources rps
                ON rps.publication_id =
                   rpl.publication_id
               AND rps.source_name =
                   rpl.source_name
            SET rpl.author_name = ?
            WHERE rpl.borrowernumber = ?
              AND rpl.source_name = ?
              AND rps.source_record_id = ?
              AND rpl.system_decision = 'confirmed'
        },
        undef,
        $args{name},
        $args{borrowernumber},
        $args{source},
        $args{record_id}
    );
}

sub extract_scopus_profile {
    my (%args) = @_;

    my $payload =
        $args{payload};

    my $response =
        ref($payload->{'author-retrieval-response'})
            eq 'ARRAY'
        ? $payload->{'author-retrieval-response'}[0]
        : {};

    my $profile =
        ref($response->{'author-profile'})
            eq 'HASH'
        ? $response->{'author-profile'}
        : {};

    my $preferred =
        ref($profile->{'preferred-name'})
            eq 'HASH'
        ? $profile->{'preferred-name'}
        : {};

    my $indexed = trim(
           $preferred->{'indexed-name'}
        || $preferred->{'ce:indexed-name'}
    );

    my $given = trim(
           $preferred->{'given-name'}
        || $preferred->{'ce:given-name'}
    );

    my $surname = trim(
           $preferred->{surname}
        || $preferred->{'ce:surname'}
    );

    my @variants;

    push @variants, {
        name       => $indexed,
        type       => 'api-indexed-name',
        path       =>
            'author-retrieval-response[0].'
            . 'author-profile.preferred-name.indexed-name',
        is_primary => 1,
    } if valid_person_name($indexed);

    if ($given ne '' && $surname ne '') {
        push @variants, {
            name       => "$given $surname",
            type       => 'api-given-surname',
            path       =>
                'author-retrieval-response[0].'
                . 'author-profile.preferred-name',
            is_primary => 0,
        };

        push @variants, {
            name       => "$surname, $given",
            type       => 'api-surname-given',
            path       =>
                'author-retrieval-response[0].'
                . 'author-profile.preferred-name',
            is_primary => 0,
        };
    }

    return (
        $indexed,
        $given,
        $surname,
        \@variants
    );
}

sub sync_scopus {
    my (%args) = @_;

    my $author_id =
        trim($args{researcher}{scopus_author_id});

    return {
        status => 'skipped',
        names  => 0,
    } if $author_id eq '';

    my $profile_url =
        source_profile_url(
            'scopus',
            $author_id
        );

    my $author_url =
        'https://api.elsevier.com/content/author/author_id/'
        . uri_escape_utf8($author_id)
        . '?view=ENHANCED';

    my $author_payload =
        get_json(
            source => 'scopus',
            url    => $author_url,
        );

    my (
        $indexed,
        $given,
        $surname,
        $profile_variants
    ) = extract_scopus_profile(
        payload => $author_payload
    );

    die "Scopus official preferred name not found\n"
        unless
            valid_person_name($indexed)
            || (
                $given ne ''
                && $surname ne ''
            );

    my @publication_payloads;
    my @publication_names;

    my $start = 0;
    my $count = 25;
    my $total = 0;

    while (1) {
        my $url =
            'https://api.elsevier.com/content/search/scopus'
            . '?query='
            . uri_escape_utf8(
                'AU-ID(' . $author_id . ')'
            )
            . '&view=COMPLETE'
            . '&count=' . $count
            . '&start=' . $start;

        my $payload =
            get_json(
                source => 'scopus',
                url    => $url,
            );

        push @publication_payloads,
            $payload;

        my $search =
            ref($payload->{'search-results'})
                eq 'HASH'
            ? $payload->{'search-results'}
            : {};

        my $entries =
            ref($search->{entry}) eq 'ARRAY'
            ? $search->{entry}
            : [];

        $total =
            $search->{'opensearch:totalResults'}
            || scalar @{$entries};

        for my $entry (@{$entries}) {
            next unless ref($entry) eq 'HASH';

            my $record_id = trim(
                   $entry->{eid}
                || $entry->{'dc:identifier'}
            );

            my $authors =
                ref($entry->{author}) eq 'ARRAY'
                ? $entry->{author}
                : [];

            for my $author (@{$authors}) {
                next unless
                    ref($author) eq 'HASH';

                next unless identifier_matches(
                    object      => $author,
                    identifiers => [$author_id],
                );

                my $name =
                    scopus_author_object_name(
                        $author
                    );

                next unless
                    valid_person_name($name);

                push @publication_names, {
                    name      => $name,
                    record_id => $record_id,
                };

                update_publication_author_name(
                    borrowernumber =>
                        $args{researcher}{borrowernumber},
                    source    => 'scopus',
                    record_id => $record_id,
                    name      => $name,
                );
            }
        }

        $start += scalar @{$entries};

        last if !@{$entries};
        last if $start >= $total;
        last if $start > 5000;
    }

    my $raw_json =
        encode_json({
            author_profile =>
                $author_payload,
            publication_pages =>
                \@publication_payloads,
        });

    # RIMS_SOURCE_NATIVE_PROFILE_DISPLAY_NAME_V1
    #
    # Scopus public author profile presents the preferred
    # author identity in surname, given order.  Do not use
    # the locally reconstructed "given surname" form for
    # profile display.
    #
    # Both surname and given are taken directly from the
    # Scopus Author Retrieval preferred-name object.
    my $display_name =
        ($surname ne '' && $given ne '')
            ? "$surname, $given"
            : (
                valid_person_name($indexed)
                    ? $indexed
                    : (
                        $surname ne ''
                            ? $surname
                            : $given
                    )
            );

    # Keep Scopus indexed-name separately as the published
    # / indexing representation.  It remains useful for
    # publication matching and disambiguation.
    my $published_name =
        valid_person_name($indexed)
            ? $indexed
            : $display_name;

    $dbh->begin_work;

    eval {
        $dbh->do(
            q{
                DELETE FROM researcher_source_name_variants
                WHERE borrowernumber = ?
                  AND source_name = 'scopus'
                  AND source_author_id = ?
            },
            undef,
            $args{researcher}{borrowernumber},
            $author_id
        );

        save_identity_cache(
            borrowernumber =>
                $args{researcher}{borrowernumber},
            source         => 'scopus',
            author_id      => $author_id,
            display_name   => $display_name,
            published_name => $published_name,
            raw_json       => $raw_json,
            method         =>
                'scopus-official-author-and-publication-api',
            profile_url    => $profile_url,
        );

        for my $variant (
            @{$profile_variants}
        ) {
            save_variant(
                borrowernumber =>
                    $args{researcher}{borrowernumber},
                source     => 'scopus',
                author_id  => $author_id,
                name       => $variant->{name},
                name_type  => $variant->{type},
                json_path  => $variant->{path},
                method     =>
                    'scopus-author-retrieval-api',
                is_primary =>
                    $variant->{is_primary},
                profile_url => $profile_url,
            );
        }

        for my $item (
            @publication_names
        ) {
            save_variant(
                borrowernumber =>
                    $args{researcher}{borrowernumber},
                source     => 'scopus',
                author_id  => $author_id,
                name       => $item->{name},
                name_type  =>
                    'publication-author-name',
                json_path  =>
                    'scopus-search-entry.author',
                method     =>
                    'scopus-publication-api-authid-match',
                is_primary => 0,
                profile_url => $profile_url,
            );
        }

        $dbh->commit;
    };

    if ($@) {
        my $error = $@;
        eval { $dbh->rollback };
        die $error;
    }

    return {
        status  => 'ok',
        names   =>
            scalar(@{$profile_variants})
            + scalar(@publication_names),
        given   => $given,
        surname => $surname,
    };
}

sub collect_hashes {
    my ($node, $output, $path) = @_;

    $path ||= 'root';

    if (ref($node) eq 'HASH') {
        push @{$output}, {
            object => $node,
            path   => $path,
        };

        for my $key (keys %{$node}) {
            collect_hashes(
                $node->{$key},
                $output,
                "$path.$key"
            );
        }
    }
    elsif (ref($node) eq 'ARRAY') {
        for my $index (
            0 .. $#{$node}
        ) {
            collect_hashes(
                $node->[$index],
                $output,
                "$path\[$index\]"
            );
        }
    }
}

sub wos_object_name {
    my ($object) = @_;

    return '' unless ref($object) eq 'HASH';

    for my $key (
        'displayName',
        'display-name',
        'publishedName',
        'published-name',
        'fullName',
        'full-name',
        'name'
    ) {
        my $value = trim($object->{$key});

        return $value
            if valid_person_name($value);
    }

    my $given = trim(
           $object->{givenName}
        || $object->{'given-name'}
        || $object->{firstName}
    );

    my $surname = trim(
           $object->{lastName}
        || $object->{surname}
        || $object->{familyName}
    );

    if ($given ne '' && $surname ne '') {
        return "$surname, $given";
    }

    return '';
}

sub name_matches_official_person {
    my (%args) = @_;

    my $name =
        normalise_name($args{name});

    my $given =
        normalise_name($args{given});

    my $surname =
        normalise_name($args{surname});

    return 0 if
        $name eq ''
        || $surname eq '';

    my @name_words =
        split /\s+/, $name;

    my %words =
        map { $_ => 1 }
        @name_words;

    return 0 unless
        $words{$surname};

    if ($given ne '') {
        my @given_words =
            split /\s+/, $given;

        my $first =
            $given_words[0] || '';

        return 1 if
            $first ne ''
            && $words{$first};

        my $initial =
            substr($first, 0, 1);

        return 1 if
            $initial ne ''
            && grep {
                $_ eq $initial
            } @name_words;

        return 0;
    }

    return 1;
}

sub sync_wos {
    my (%args) = @_;

    my $author_id =
        trim($args{researcher}{researcher_id});

    my $orcid =
        trim($args{researcher}{orcid});

    return {
        status => 'skipped',
        names  => 0,
    } if $author_id eq '';

    my $profile_url =
        source_profile_url(
            'wos',
            $author_id
        );

    my @pages;
    my @matched_names;
    my %seen_names;

    my $page = 1;
    my $limit = 50;
    my $total = 0;

    while (1) {
        my $url =
            'https://api.clarivate.com/apis/'
            . 'wos-starter/v1/documents'
            . '?db='
            . uri_escape_utf8($wos_db)
            . '&q='
            . uri_escape_utf8(
                'AI=' . $author_id
            )
            . '&limit=' . $limit
            . '&page=' . $page;

        my $payload =
            get_json(
                source => 'wos',
                url    => $url,
            );

        push @pages, $payload;

        my $hits =
            ref($payload->{hits}) eq 'ARRAY'
            ? $payload->{hits}
            : [];

        my $metadata =
            ref($payload->{metadata}) eq 'HASH'
            ? $payload->{metadata}
            : {};

        $total =
               $metadata->{total}
            || $metadata->{totalResults}
            || scalar @{$hits};

        for my $hit (@{$hits}) {
            next unless ref($hit) eq 'HASH';

            my $record_id = trim(
                   $hit->{uid}
                || $hit->{UT}
                || $hit->{id}
            );

            my @objects;

            collect_hashes(
                $hit,
                \@objects,
                'hit'
            );

            my @identifier_matches;

            for my $candidate (@objects) {
                if (
                    identifier_matches(
                        object =>
                            $candidate->{object},
                        identifiers =>
                            [$author_id, $orcid],
                    )
                ) {
                    push @identifier_matches,
                        $candidate;
                }
            }

            my @accepted;

            for my $candidate (
                @identifier_matches
            ) {
                my $name =
                    wos_object_name(
                        $candidate->{object}
                    );

                next unless
                    valid_person_name($name);

                push @accepted, {
                    name => $name,
                    path => $candidate->{path},
                };
            }

            if (!@accepted) {
                my $names =
                    ref($hit->{names}) eq 'HASH'
                    ? $hit->{names}
                    : {};

                my $authors =
                    ref($names->{authors}) eq 'ARRAY'
                    ? $names->{authors}
                    : [];

                my @fallback;

                for my $index (
                    0 .. $#{$authors}
                ) {
                    my $author =
                        $authors->[$index];

                    next unless
                        ref($author) eq 'HASH';

                    my $name =
                        wos_object_name($author);

                    next unless
                        valid_person_name($name);

                    next unless
                        name_matches_official_person(
                            name    => $name,
                            given   => $args{scopus_given},
                            surname => $args{scopus_surname},
                        );

                    push @fallback, {
                        name => $name,
                        path =>
                            "hit.names.authors[$index]",
                    };
                }

                # Fallback is accepted only when exactly one
                # publication author matches the API-derived
                # Scopus given name and surname.
                @accepted = @fallback
                    if @fallback == 1;
            }

            for my $accepted (@accepted) {
                my $key =
                    normalise_name(
                        $accepted->{name}
                    );

                next if $key eq '';

                $seen_names{
                    $accepted->{name}
                } = $accepted->{path};

                update_publication_author_name(
                    borrowernumber =>
                        $args{researcher}{borrowernumber},
                    source    => 'wos',
                    record_id => $record_id,
                    name      => $accepted->{name},
                );
            }
        }

        last if !@{$hits};
        last if $page * $limit >= $total;
        last if $page >= 100;

        $page++;
    }

    @matched_names =
        sort keys %seen_names;

    # RIMS_WOS_CONFIRMED_PUBLICATION_EVIDENCE_FALLBACK_V3
    #
    # WoS may assign/merge a claimed ResearcherID after a publication
    # was indexed under an older algorithmic author-record ID.
    #
    # If AI=<current authoritative ResearcherID> cannot resolve a
    # source-native author name, use ONLY publications that are already
    # confirmed for this researcher and already have a WoS provenance
    # record in researcher_publication_sources.
    #
    # The fallback does not trust the legacy researcherId as identity.
    # Candidate authors are matched against the official Scopus-derived
    # given/surname evidence.  A name is accepted only when exactly one
    # author in a confirmed publication matches.
    #
    # No borrower number, DOI, person name, or legacy identifier is
    # hard-coded.

    if (!@matched_names) {

        my $evidence_rows =
            $dbh->selectall_arrayref(
                q{
                    SELECT DISTINCT
                        rpl.publication_id,
                        rps.source_record_id,
                        rps.raw_json
                    FROM researcher_publication_links rpl
                    INNER JOIN researcher_publication_sources rps
                      ON rps.publication_id = rpl.publication_id
                     AND rps.source_name = 'wos'
                    WHERE rpl.borrowernumber = ?
                      AND rpl.source_name = 'wos'
                      AND rpl.source_author_id = ?
                      AND rpl.system_decision = 'confirmed'
                      AND rpl.review_status IN (
                          'confirmed',
                          'auto_confirmed'
                      )
                      AND rps.raw_json IS NOT NULL
                      AND TRIM(rps.raw_json) <> ''
                    ORDER BY rpl.publication_id
                },
                { Slice => {} },
                $args{researcher}{borrowernumber},
                $author_id
            ) || [];

        for my $row (@{$evidence_rows}) {

            my $record_id =
                trim($row->{source_record_id});

            my $payload;

            eval {
                $payload =
                    decode_json($row->{raw_json});
            };

            next if $@;
            next unless ref($payload) eq 'HASH';

            my $names =
                ref($payload->{names}) eq 'HASH'
                ? $payload->{names}
                : {};

            my $authors =
                ref($names->{authors}) eq 'ARRAY'
                ? $names->{authors}
                : [];

            my @fallback;

            for my $index (0 .. $#{$authors}) {

                my $author =
                    $authors->[$index];

                next unless ref($author) eq 'HASH';

                my $name =
                    wos_object_name($author);

                next unless
                    valid_person_name($name);

                next unless
                    name_matches_official_person(
                        name    => $name,
                        given   => $args{scopus_given},
                        surname => $args{scopus_surname},
                    );

                push @fallback, {
                    name => $name,
                    path =>
                        "confirmed_wos_publication[$record_id]"
                        . ".names.authors[$index]",
                };
            }

            # Safety rule:
            # accept only one uniquely matching author in this record.
            next unless @fallback == 1;

            my $accepted =
                $fallback[0];

            my $key =
                normalise_name(
                    $accepted->{name}
                );

            next if $key eq '';

            $seen_names{
                $accepted->{name}
            } = $accepted->{path};

            update_publication_author_name(
                borrowernumber =>
                    $args{researcher}{borrowernumber},
                source    => 'wos',
                record_id => $record_id,
                name      => $accepted->{name},
            );
        }

        @matched_names =
            sort keys %seen_names;
    }

    die "No exact WoS API author name matched "
        . "Researcher ID/ORCID, official API name, "
        . "or uniquely matched confirmed WoS publication evidence\\n"
        unless @matched_names;

    # RIMS_SOURCE_NATIVE_PROFILE_DISPLAY_NAME_V1
    #
    # matched_names contains names accepted from the
    # identifier-bound WoS API evidence.  Never rewrite,
    # reorder or choose a value merely because it is the
    # longest spelling.
    #
    # Keep the API representation itself.
    my $primary =
        $matched_names[0];

    my $raw_json =
        encode_json({
            query_researcher_id =>
                $author_id,
            pages => \@pages,
        });

    $dbh->begin_work;

    eval {
        $dbh->do(
            q{
                DELETE FROM researcher_source_name_variants
                WHERE borrowernumber = ?
                  AND source_name = 'wos'
                  AND source_author_id = ?
            },
            undef,
            $args{researcher}{borrowernumber},
            $author_id
        );

        save_identity_cache(
            borrowernumber =>
                $args{researcher}{borrowernumber},
            source         => 'wos',
            author_id      => $author_id,
            display_name   => $primary,
            published_name => $primary,
            raw_json       => $raw_json,
            method         =>
                (
                    grep {
                        ($seen_names{$_} || '') =~
                            /^confirmed_wos_publication\[/
                    } @matched_names
                )
                ? 'wos-confirmed-publication-source-evidence'
                : 'wos-starter-api-identifier-bound',
            profile_url    => $profile_url,
        );

        for my $name (@matched_names) {
            save_variant(
                borrowernumber =>
                    $args{researcher}{borrowernumber},
                source     => 'wos',
                author_id  => $author_id,
                name       => $name,
                name_type  =>
                    'api-publication-display-name',
                json_path  =>
                    $seen_names{$name},
                method     =>
                    (
                        ($seen_names{$name} || '') =~
                            /^confirmed_wos_publication\[/
                    )
                    ? 'wos-confirmed-publication-source-evidence'
                    : 'wos-starter-api-identifier-bound',
                is_primary =>
                    $name eq $primary ? 1 : 0,
                profile_url => $profile_url,
            );
        }

        $dbh->commit;
    };

    if ($@) {
        my $error = $@;
        eval { $dbh->rollback };
        die $error;
    }

    return {
        status => 'ok',
        names  => scalar @matched_names,
    };
}

my @where = (
    q{c.verification_status = 'verified'},
    q{c.employment_status = 'active'},
    q{c.sync_enabled = 1},
);

my @bind;

if ($borrowernumber) {
    push @where,
        q{c.borrowernumber = ?};

    push @bind,
        $borrowernumber;
}

my $researchers =
    $dbh->selectall_arrayref(
        q{
            SELECT
                c.borrowernumber,

                /* RIMS_AUTHOR_NAME_AUTHORITATIVE_IDENTIFIER_GATE_V2 */
                sc.identifier_value AS scopus_author_id,
                wi.identifier_value AS researcher_id,
                oi.identifier_value AS orcid,

                c.preferred_name,
                c.official_name

            FROM custom_profile_details c

            LEFT JOIN researcher_identifiers sc
              ON sc.borrowernumber = c.borrowernumber
             AND sc.identifier_type = 'scopus'
             AND sc.verification_status = 'verified'
             AND sc.is_primary = 1
             AND sc.is_active = 1

            LEFT JOIN researcher_identifiers wi
              ON wi.borrowernumber = c.borrowernumber
             AND wi.identifier_type = 'wos'
             AND wi.verification_status = 'verified'
             AND wi.is_primary = 1
             AND wi.is_active = 1

            LEFT JOIN researcher_identifiers oi
              ON oi.borrowernumber = c.borrowernumber
             AND oi.identifier_type = 'orcid'
             AND oi.verification_status = 'verified'
             AND oi.is_primary = 1
             AND oi.is_active = 1

            WHERE
        }
        . join(' AND ', @where)
        . q{
            ORDER BY c.borrowernumber
        },
        { Slice => {} },
        @bind
    ) || [];

die "No eligible researcher found\n"
    unless @{$researchers};

my %summary = (
    researchers    => 0,
    scopus_ok      => 0,
    wos_ok         => 0,
    scopus_names   => 0,
    wos_names      => 0,
    errors         => 0,
);

for my $researcher (@{$researchers}) {
    $summary{researchers}++;

    my $bn =
        $researcher->{borrowernumber};

    print "\n";
    print "============================================================\n";
    print "Researcher borrowernumber: $bn\n";
    print "============================================================\n";

    my $scopus_result;

    eval {
        $scopus_result =
            sync_scopus(
                researcher => $researcher,
            );
    };

    if ($@) {
        $summary{errors}++;

        warn "SCOPUS_ERROR: $@\n";
    }
    elsif (
        $scopus_result->{status}
        eq 'ok'
    ) {
        $summary{scopus_ok}++;
        $summary{scopus_names} +=
            $scopus_result->{names};

        print "SCOPUS_OFFICIAL_API_OK\n";
        print "Scopus names processed: "
            . $scopus_result->{names}
            . "\n";
    }
    else {
        print "SCOPUS_SKIPPED\n";
    }

    my $wos_result;

    eval {
        $wos_result =
            sync_wos(
                researcher     => $researcher,
                scopus_given   =>
                    $scopus_result
                    && $scopus_result->{status}
                        eq 'ok'
                    ? $scopus_result->{given}
                    : '',
                scopus_surname =>
                    $scopus_result
                    && $scopus_result->{status}
                        eq 'ok'
                    ? $scopus_result->{surname}
                    : '',
            );
    };

    if ($@) {
        $summary{errors}++;

        warn "WOS_ERROR: $@\n";
    }
    elsif (
        $wos_result->{status}
        eq 'ok'
    ) {
        $summary{wos_ok}++;
        $summary{wos_names} +=
            $wos_result->{names};

        print "WOS_OFFICIAL_API_OK\n";
        print "WoS names processed: "
            . $wos_result->{names}
            . "\n";
    }
    else {
        print "WOS_SKIPPED\n";
    }
}

print "\n";
print "============================================================\n";
print "OFFICIAL API AUTHOR NAME SYNC SUMMARY\n";
print "============================================================\n";

for my $key (
    qw(
        researchers
        scopus_ok
        wos_ok
        scopus_names
        wos_names
        errors
    )
) {
    print "$key=$summary{$key}\n";
}

if ($summary{errors}) {
    die "OFFICIAL_API_AUTHOR_NAMES_SYNC_COMPLETED_WITH_ERRORS\n";
}

print "OFFICIAL_API_AUTHOR_NAMES_SYNC_OK\n";

exit 0;
