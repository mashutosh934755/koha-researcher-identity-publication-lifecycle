#!/usr/bin/perl

use strict;
use warnings;

use CGI qw(-utf8);
use JSON qw(
    encode_json
    decode_json
);
use HTTP::Tiny;

my $cgi = CGI->new;

print $cgi->header(
    -type    => 'application/json',
    -charset => 'utf-8',
    -status  => '200 OK',
);


sub fail_json {
    my (%args) = @_;

    print encode_json({
        ok       => JSON::false,
        source   => $args{source} // 'server',
        error    => $args{error}  // 'Unknown error',
        fallback => JSON::true,
    });

    exit 0;
}


# ======================================================
# INPUT
# ======================================================

my $question =
    $cgi->param('q') // '';

$question =~ s/^\s+|\s+$//g;

if (!$question) {
    fail_json(
        source => 'validation',
        error  => 'Research question is required',
    );
}

if (length($question) > 1500) {
    fail_json(
        source => 'validation',
        error  => 'Research question is too long',
    );
}


# ======================================================
# SECRET
# ======================================================

my $secret_file =
    '/etc/koha/sites/INSTANCE/gemini-expert-discovery.conf';

open my $fh, '<', $secret_file
    or fail_json(
        source => 'configuration',
        error  => 'AI query configuration is unavailable',
    );

my $api_key = '';

while (my $line = <$fh>) {

    chomp $line;

    if (
        $line =~
        /^GEMINI_API_KEY=(.+)$/
    ) {
        $api_key = $1;
        last;
    }
}

close $fh;

if (!$api_key) {
    fail_json(
        source => 'configuration',
        error  => 'AI query API key is not configured',
    );
}


# ======================================================
# STRUCTURED PROMPT
# ======================================================

my $prompt = <<"PROMPT";
You are the query-understanding component of Example University Library's
institutional expert discovery system.

Analyse ONLY the research question.

Do not recommend researchers.
Do not invent publications.
Do not infer Example University staff identities.
Return neutral structured research concepts only.

Research question:
$question
PROMPT


my $payload = {
    model => 'gemini-3.6-flash',

    input => $prompt,

    store => JSON::false,

    generation_config => {
        thinking_level => 'minimal',
        temperature    => 0,
    },

    response_format => {
        type      => 'text',
        mime_type => 'application/json',

        schema => {
            type => 'object',

            properties => {

                primary_topic => {
                    type => 'string',
                },

                research_domain => {
                    type => 'string',
                },

                context => {
                    type  => 'array',
                    items => {
                        type => 'string',
                    },
                },

                methodologies => {
                    type  => 'array',
                    items => {
                        type => 'string',
                    },
                },

                related_concepts => {
                    type  => 'array',
                    items => {
                        type => 'string',
                    },
                },

                keywords => {
                    type  => 'array',
                    items => {
                        type => 'string',
                    },
                },

                query_intent => {
                    type => 'string',

                    enum => [
                        'topic_expert',
                        'methodology_expert',
                        'interdisciplinary_expert',
                        'collaboration_search',
                        'general_expert_search',
                    ],
                },
            },

            required => [
                'primary_topic',
                'research_domain',
                'context',
                'methodologies',
                'related_concepts',
                'keywords',
                'query_intent',
            ],
        },
    },
};


# ======================================================
# GEMINI CALL
# ======================================================

my $http = HTTP::Tiny->new(
    timeout => 45,
    verify_SSL => 1,
);

my $url =
    'https://generativelanguage.googleapis.com/'
    . 'v1beta/interactions';

my $response =
    $http->post(
        $url,
        {
            headers => {
                'Content-Type'
                    => 'application/json',

                'x-goog-api-key'
                    => $api_key,
            },

            content =>
                encode_json($payload),
        }
    );


if (!$response->{success}) {

    my $status =
        $response->{status} // '';

    my $reason =
        $response->{reason} // '';

    fail_json(
        source => 'gemini',
        error  => "Gemini request failed: $status $reason",
    );
}


# ======================================================
# PARSE GEMINI RESPONSE
# ======================================================

my $outer;

eval {
    $outer =
        decode_json(
            $response->{content}
        );
};

if ($@ || !$outer) {
    fail_json(
        source => 'gemini',
        error  => 'Invalid Gemini response',
    );
}


if ($outer->{error}) {

    my $message =
        $outer->{error}->{message}
        // 'Gemini API error';

    fail_json(
        source => 'gemini',
        error  => $message,
    );
}


my @texts;

for my $step (
    @{ $outer->{steps} // [] }
) {

    next
        unless
        ($step->{type} // '')
        eq 'model_output';

    for my $part (
        @{ $step->{content} // [] }
    ) {

        next
            unless
            ($part->{type} // '')
            eq 'text';

        my $text =
            $part->{text} // '';

        push @texts, $text
            if $text ne '';
    }
}


my $model_text =
    join(
        "\n",
        @texts
    );

$model_text =~
    s/^\s+|\s+$//g;


if (!$model_text) {
    fail_json(
        source => 'gemini',
        error  => 'Gemini returned no structured text',
    );
}


my $concepts;

eval {
    $concepts =
        decode_json(
            $model_text
        );
};

if ($@ || ref($concepts) ne 'HASH') {
    fail_json(
        source => 'gemini',
        error  => 'Gemini structured output was invalid',
    );
}


# ======================================================
# BUILD SEARCH EXPANSION
# ======================================================

my @terms;

push @terms,
    $concepts->{primary_topic}
    if $concepts->{primary_topic};

push @terms,
    $concepts->{research_domain}
    if $concepts->{research_domain};

push @terms,
    @{ $concepts->{context} // [] };

push @terms,
    @{ $concepts->{methodologies} // [] };

push @terms,
    @{ $concepts->{related_concepts} // [] };

push @terms,
    @{ $concepts->{keywords} // [] };


my %seen;

@terms =
    grep {
        defined($_)
        &&
        $_ ne ''
        &&
        !$seen{lc($_)}++
    }
    @terms;


print encode_json({
    ok => JSON::true,

    source =>
        'gemini-3.6-flash',

    original_question =>
        $question,

    concepts =>
        $concepts,

    expanded_terms =>
        \@terms,

    fallback =>
        JSON::false,
});

exit 0;
