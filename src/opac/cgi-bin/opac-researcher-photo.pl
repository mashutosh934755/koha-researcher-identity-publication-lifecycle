#!/usr/bin/perl
use Modern::Perl;
use CGI qw(-utf8);
use C4::Context;

my $q = CGI->new;
my $borrowernumber = $q->param('id') // '';
$borrowernumber =~ s/D//g;

print $q->header(-status => '404 Not Found', -type => 'text/plain; charset=utf-8'), "Not found
"
    and exit unless $borrowernumber;

my $dbh = C4::Context->dbh;
my ($visible) = $dbh->selectrow_array(
    q{
      SELECT COUNT(*)
      FROM custom_profile_details
      WHERE borrowernumber=?
        AND verification_status='verified'
        AND public_visibility=1
        AND employment_status IN ('active','former')
    },
    undef,
    $borrowernumber
);
print $q->header(-status => '404 Not Found', -type => 'text/plain; charset=utf-8'), "Not found
"
    and exit unless $visible;

my ($image) = $dbh->selectrow_array(
    q{SELECT imagefile FROM patronimage WHERE borrowernumber=?},
    undef,
    $borrowernumber
);
print $q->header(-status => '404 Not Found', -type => 'text/plain; charset=utf-8'), "Not found
"
    and exit unless defined $image && length $image;

print $q->header(
    -type => 'image/jpeg',
    -expires => '+1h',
    -cache_control => 'public, max-age=3600'
);
binmode STDOUT;
print $image;
