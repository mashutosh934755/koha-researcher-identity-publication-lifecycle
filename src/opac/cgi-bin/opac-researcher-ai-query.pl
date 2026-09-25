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

sub read_config {
    my ($file) = @_;
    my %cfg;

    open my $fh, '<', $file
        or return %cfg;

    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /^\s*#/;
        next unless $line =~ /^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/;

        my ($key, $value) = ($1, $2);
        $value =~ s/^"(.*)"$/$1/;
        $value =~ s/^'(.*)'$/$1/;
        $cfg{$key} = $value;
    }

    close $fh;
    return %cfg;
}

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

my $secret_file =
    '/etc/koha/sites/INSTANCE/deepseek-expert-discovery.conf';

my %cfg =
    read_config($secret_file);

my $api_key =
    $cfg{DEEPSEEK_API_KEY} // '';

my $model =
    $cfg{DEEPSEEK_MODEL}
    || 'deepseek-flash';

my $base_url =
    $cfg{DEEPSEEK_BASE_URL}
    || 'https://api.deepseek.com';

my $timeout =
    $cfg{DEEPSEEK_TIMEOUT_SECONDS}
    || 45;

if (!$api_key) {
    fail_json(
        source => 'configuration',
        error  => 'DeepSeek API key is not configured',
    );
}

$base_url =~ s{/+$}{};

my $system_prompt = <<'PROMPT';
You are the query-understanding component of an institutional
library expert-discovery system.

Interpret the research question only.

Do not recommend or rank researchers.
Do not use external knowledge about institutional staff.
Do not invent identities, affiliations, publications or expertise.

Return JSON only with these keys:
primary_topic, research_domain, context, methodologies,
related_concepts, keywords, query_intent.

Keep concepts concise and useful for matching against verified
local researcher evidence.
PROMPT

my $user_prompt =
    "Research question:\n"
    . $question;

my $payload = {
    model => $model,
    messages => [
        {
            role    => 'system',
            content => $system_prompt,
        },
        {
            role    => 'user',
            content => $user_prompt,
        },
    ],
    temperature => 0,
    response_format => {
        type => 'json_object',
    },
};

my $http = HTTP::Tiny->new(
    timeout    => $timeout,
    verify_SSL => 1,
);

my $response =
    $http->post(
        $base_url . '/chat/completions',
        {
            headers => {
                'Content-Type'
                    => 'application/json',

                'Authorization'
                    => 'Bearer ' . $api_key,
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
        source => 'deepseek',
        error  => "DeepSeek request failed: $status $reason",
    );
}

my $outer;

eval {
    $outer =
        decode_json(
            $response->{content}
        );
};

if ($@ || !$outer) {
    fail_json(
        source => 'deepseek',
        error  => 'Invalid DeepSeek response',
    );
}

if ($outer->{error}) {
    my $message =
        ref($outer->{error}) eq 'HASH'
        ? ($outer->{error}->{message} // 'DeepSeek API error')
        : 'DeepSeek API error';

    fail_json(
        source => 'deepseek',
        error  => $message,
    );
}

my $model_text =
    $outer->{choices}->[0]->{message}->{content}
    // '';

$model_text =~ s/^\s+|\s+$//g;
$model_text =~ s/^\`\`\`(?:json)?\s*//i;
$model_text =~ s/\s*\`\`\`$//;

if (!$model_text) {
    fail_json(
        source => 'deepseek',
        error  => 'DeepSeek returned no structured text',
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
        source => 'deepseek',
        error  => 'DeepSeek structured output was invalid',
    );
}

for my $key (
    qw(
        context
        methodologies
        related_concepts
        keywords
    )
) {
    $concepts->{$key} = []
        unless ref($concepts->{$key}) eq 'ARRAY';
}

for my $key (
    qw(
        primary_topic
        research_domain
        query_intent
    )
) {
    $concepts->{$key} =
        ''
        unless defined $concepts->{$key};
}

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
        'deepseek',

    model =>
        $model,

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
