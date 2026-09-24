#!/usr/bin/perl

use Modern::Perl;
use CGI qw(-utf8);
use C4::Context;

my $query = CGI->new;
my $id    = scalar $query->param('id') // '';

sub not_found {
    print $query->header(
        -status        => '404 Not Found',
        -type          => 'text/plain; charset=utf-8',
        -cache_control => 'private, no-store',
    );

    print "Researcher photo not available.\n";
    exit;
}

not_found()
    unless $id =~ /^\d+$/;

my $dbh = C4::Context->dbh;

my $researcher = $dbh->selectrow_hashref(
    q{
        SELECT
            c.borrowernumber
        FROM custom_profile_details c
        WHERE c.borrowernumber = ?
          AND c.verification_status = 'verified'
          AND c.public_visibility = 1
          AND c.employment_status IN ('active', 'former')
        LIMIT 1
    },
    undef,
    $id
);

not_found()
    unless $researcher;

my $table_exists = $dbh->selectrow_array(
    q{
        SELECT COUNT(*)
        FROM information_schema.tables
        WHERE table_schema = DATABASE()
          AND table_name = 'patronimage'
    }
);

not_found()
    unless $table_exists;

my $photo = $dbh->selectrow_hashref(
    q{
        SELECT
            mimetype,
            imagefile
        FROM patronimage
        WHERE borrowernumber = ?
        LIMIT 1
    },
    undef,
    $id
);

not_found()
    unless $photo
        && defined $photo->{imagefile}
        && length $photo->{imagefile};

my $mimetype = $photo->{mimetype} || 'image/jpeg';

$mimetype = 'image/jpeg'
    unless $mimetype =~ m{\Aimage/(?:jpeg|png|gif|webp)\z}i;

binmode STDOUT;

print $query->header(
    -type          => $mimetype,
    -expires       => '+1h',
    -cache_control => 'public, max-age=3600',
);

print $photo->{imagefile};
