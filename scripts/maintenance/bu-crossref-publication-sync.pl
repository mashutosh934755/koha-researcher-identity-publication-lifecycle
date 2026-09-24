#!/usr/bin/perl
use Modern::Perl;
use C4::Context;
use HTTP::Request;
use JSON::MaybeXS qw(decode_json encode_json);
use LWP::UserAgent;
use URI::Escape qw(uri_escape_utf8);
use Time::HiRes qw(sleep);
use Getopt::Long qw(GetOptions);

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $apply = 0;
my $limit = 0;
my $publication_id = 0;
GetOptions('apply'=>$apply,'limit=i'=>$limit,'publication-id=i'=>$publication_id) or die "Invalid arguments
";
my $dbh = C4::Context->dbh;
die "Koha database connection unavailable
" unless $dbh;

sub clean { my ($v)=@_; return '' unless defined $v; $v="$v"; $v=~s/^s+|s+$//g; return $v; }
sub normalize_doi { my ($d)=@_; $d=lc clean($d); $d=~s{^https?://(?:dx.)?doi.org/}{}; $d=~s/^doi:s*//; $d=~s/s+//g; $d=~s/[.,;]+$//; return $d; }
sub normalize_title { my ($t)=@_; $t=lc clean($t); $t=~s/&amp;/ and /g; $t=~s/[^a-z0-9]+/ /g; $t=~s/s+/ /g; $t=~s/^s+|s+$//g; return $t; }
sub token_similarity {
    my ($l,$r)=@_; $l=normalize_title($l); $r=normalize_title($r);
    return 0 unless length($l)&&length($r); return 1 if $l eq $r;
    my %a=map {$_=>1} grep {length($_)>1} split /s+/,$l;
    my %b=map {$_=>1} grep {length($_)>1} split /s+/,$r;
    my %all=(%a,%b); my ($i,$u)=(0,0);
    for my $t(keys %all){$u++;$i++ if $a{$t}&&$b{$t};}
    return $u ? $i/$u : 0;
}
sub first_value {
    my ($v)=@_; return '' unless defined $v;
    if(ref($v) eq 'ARRAY'){ return @$v ? first_value($v->[0]) : ''; }
    if(ref($v) eq 'HASH'){ for my $k(qw(value name title source publisher)){ return first_value($v->{$k}) if exists $v->{$k}; } return ''; }
    return clean($v);
}
sub crossref_year {
    my ($m)=@_;
    for my $f(qw(published-print published-online published issued created)){
        my $v=$m->{$f}; next unless ref($v) eq 'HASH';
        my $p=$v->{'date-parts'}; next unless ref($p) eq 'ARRAY' && ref($p->[0]) eq 'ARRAY';
        my $y=$p->[0][0]; return $y if defined $y && $y =~ /^d{4}$/;
    }
    return undef;
}
sub crossref_lookup {
    my ($doi)=@_;
    my $ua=LWP::UserAgent->new(timeout=>35,agent=>'Koha-RIMS-Crossref/1.0 (mailto:library@example.edu)');
    my $request=HTTP::Request->new(GET=>"https://api.crossref.org/works/".uri_escape_utf8($doi));
    $request->header(Accept=>'application/json');
    my $response=$ua->request($request);
    return (undef,$response->code,$response->status_line) unless $response->is_success;
    my $payload; eval {$payload=decode_json($response->decoded_content);};
    return (undef,$response->code,'Invalid Crossref JSON response') if $@ || ref($payload) ne 'HASH';
    return ($payload,$response->code,'');
}

my @conditions=(q{doi IS NOT NULL AND TRIM(doi) <> ''});
my @bind;
if($publication_id){push @conditions,'id = ?'; push @bind,$publication_id;}
my $sql=q{SELECT id,publication_key,doi,title,journal,publication_year,document_type FROM researcher_publications_master WHERE }.join(' AND ',@conditions).' ORDER BY id';
$sql.=' LIMIT '.int($limit) if $limit && $limit>0;
my $publications=$dbh->selectall_arrayref($sql,{Slice=>{}},@bind)||[];
my $found=scalar @$publications;
my $job_id;

if($apply){
    $dbh->do(q{
      INSERT INTO researcher_sync_jobs
      (borrowernumber,source_name,job_type,job_status,records_found,metadata_json)
      VALUES (NULL,'crossref','manual','running',?,?)
    },undef,$found,encode_json({mode=>'existing_doi_verification',automatic_doi_insertion=>0,publication_id_filter=>$publication_id||undef,limit=>$limit||undef}));
    $job_id=$dbh->{mysql_insertid};
}

my %summary=(found=>$found,processed=>0,verified=>0,inserted=>0,updated=>0,held=>0,not_found=>0,lookup_failed=>0,doi_mismatch=>0,title_mismatch=>0,database_changes=>$apply?'CROSSREF_SOURCE_ROWS_ONLY':'NONE',publication_doi_changes=>0);
my @results;

eval {
    $dbh->{AutoCommit}=0 if $apply;
    for my $publication(@$publications){
        my $local_doi=normalize_doi($publication->{doi});
        my ($payload,$http_code,$error)=crossref_lookup($local_doi);
        $summary{processed}++;
        if(!$payload){
            $http_code==404 ? $summary{not_found}++ : $summary{lookup_failed}++;
            push @results,{publication_id=>$publication->{id},doi=>$local_doi,decision=>$http_code==404?'not_found':'lookup_failed',http_code=>$http_code,error=>$error};
            sleep 0.25; next;
        }
        my $message=$payload->{message};
        unless(ref($message) eq 'HASH'){
            $summary{lookup_failed}++; push @results,{publication_id=>$publication->{id},doi=>$local_doi,decision=>'lookup_failed',error=>'Crossref message missing'}; sleep 0.25; next;
        }
        my $crossref_doi=normalize_doi($message->{DOI});
        my $crossref_title=first_value($message->{title});
        my $crossref_journal=first_value($message->{'container-title'});
        my $crossref_publisher=first_value($message->{publisher});
        my $crossref_year=crossref_year($message);
        my $similarity=token_similarity($publication->{title},$crossref_title);
        my $doi_exact=$local_doi && $crossref_doi && $local_doi eq $crossref_doi ? 1:0;
        my $title_safe=$similarity>=0.72?1:0;
        my $year_safe=1;
        if($publication->{publication_year} && $crossref_year){
            $year_safe=abs($publication->{publication_year}-$crossref_year)<=1?1:0;
        }
        my $decision=$doi_exact && $title_safe && $year_safe ? 'verified':'hold_for_manual_review';
        $summary{doi_mismatch}++ unless $doi_exact;
        $summary{title_mismatch}++ unless $title_safe;
        my $citation_count=$message->{'is-referenced-by-count'};
        $citation_count=undef unless defined $citation_count && "$citation_count" =~ /^d+$/;
        my $source_url=clean($message->{URL});
        $source_url="https://doi.org/$crossref_doi" unless $source_url =~ m{^https?://}i;
        my $verification={decision=>$decision,verified_at=>scalar localtime(),doi_exact=>$doi_exact,title_similarity=>$similarity,year_safe=>$year_safe,crossref_title=>$crossref_title,crossref_journal=>$crossref_journal,crossref_publisher=>$crossref_publisher,crossref_year=>$crossref_year};
        if($decision eq 'verified'){
            $summary{verified}++;
            if($apply){
                my ($existing_id)=$dbh->selectrow_array(q{SELECT id FROM researcher_publication_sources WHERE source_name='crossref' AND source_record_id=?},undef,$crossref_doi);
                if($existing_id){
                    $dbh->do(q{UPDATE researcher_publication_sources SET publication_id=?,source_url=?,citation_count=?,raw_json=?,last_synced_at=NOW() WHERE id=?},undef,$publication->{id},$source_url,$citation_count,encode_json({crossref=>$message,verification=>$verification}),$existing_id);
                    $summary{updated}++;
                } else {
                    $dbh->do(q{INSERT INTO researcher_publication_sources (publication_id,source_name,source_record_id,source_url,citation_count,raw_json) VALUES (?,'crossref',?,?,?,?,?)},undef,$publication->{id},$crossref_doi,$source_url,$citation_count,encode_json({crossref=>$message,verification=>$verification}));
                    $summary{inserted}++;
                }
            }
        } else {
            $summary{held}++;
        }
        push @results,{publication_id=>$publication->{id},doi=>$local_doi,decision=>$decision,title_similarity=>$similarity,crossref_year=>$crossref_year};
        sleep 0.25;
    }
    if($apply){
        $dbh->do(q{UPDATE researcher_sync_jobs SET job_status='completed',completed_at=NOW(),records_processed=?,records_added=?,records_updated=?,metadata_json=? WHERE id=?},undef,$summary{processed},$summary{inserted},$summary{updated},encode_json({summary=>%summary,results=>@results}),$job_id);
        $dbh->commit;
    }
    1;
} or do {
    my $err=$@ || 'Unknown error';
    if($apply){
        eval {$dbh->rollback;};
        eval {$dbh->do(q{UPDATE researcher_sync_jobs SET job_status='failed',completed_at=NOW(),error_message=? WHERE id=?},undef,$err,$job_id);};
    }
    die $err;
};

print encode_json({summary=>%summary,results=>@results}),"
";
