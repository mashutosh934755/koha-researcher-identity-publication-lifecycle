#!/usr/bin/perl
use Modern::Perl;
use C4::Context;

my $dbh=C4::Context->dbh;
my $instance=$ENV{KOHA_INSTANCE}||'INSTANCE';
if($ENV{KOHA_CONF} && $ENV{KOHA_CONF}=~m{/etc/koha/sites/([^/]+)/koha-conf.xml}){$instance=$1;}
my %runtime_env;
my $env_file="/etc/koha/sites/$instance/research-api.env";
if(-f $env_file && open my $efh,'<',$env_file){
  while(my $line=<$efh>){chomp $line; next if $line =~ /^s*(?:#|$)/; if($line =~ /^([A-Z0-9_]+)=(.*)$/){my($k,$v)=($1,$2);$v=~s/^['"]|['"]$//g;$runtime_env{$k}=$v;}}
  close $efh;
}
my $institution_name=$ENV{RIMS_INSTITUTION_NAME}||$runtime_env{RIMS_INSTITUTION_NAME}||'Example University';

sub trim{my($v)=@_;$v='' unless defined $v;$v="$v";$v=~s/^s+//;$v=~s/s+$//;return $v;}
sub normalise_name{my($v)=@_;$v=lc trim($v);$v=~s/[^a-z0-9]+/ /g;$v=~s/s+/ /g;$v=~s/^s+|s+$//g;return $v;}
sub contains_institution{my($v)=@_;my $n=lc trim($institution_name);return 0 if $n eq '';return index(lc(trim($v)),$n)>=0?1:0;}

my $links=$dbh->selectall_arrayref(q{
SELECT l.id,l.borrowernumber,l.publication_id,l.source_name,l.source_author_id,l.author_name,l.affiliation_status,l.match_score,l.system_decision,l.review_status,
c.preferred_name,c.official_name,c.alternative_name,c.main_affiliation,c.affiliation_organisation,c.employment_status,c.verification_status,
p.title,p.doi,p.publication_year
FROM researcher_publication_links l
JOIN custom_profile_details c ON c.borrowernumber=l.borrowernumber
JOIN researcher_publications_master p ON p.id=l.publication_id
},{Slice=>{}})||[];

my($confirmed,$reviewed,$rejected)=(0,0,0);
for my $row(@$links){
  my($identifier_score,$name_score,$affiliation_score,$timeline_score)=(0,0,0,0);
  my $source_author_id=trim($row->{source_author_id});
  my $identifier_type=$row->{source_name} eq 'scopus'?'scopus':$row->{source_name} eq 'wos'?'wos':'';
  if($identifier_type ne '' && $source_author_id ne ''){
    my($m)=$dbh->selectrow_array(q{SELECT COUNT(*) FROM researcher_identifiers WHERE borrowernumber=? AND identifier_type=? AND identifier_value=? AND verification_status='verified' AND is_primary=1 AND is_active=1},undef,$row->{borrowernumber},$identifier_type,$source_author_id);
    $identifier_score=55 if($m||0)==1;
  }
  my $candidate=normalise_name($row->{author_name});
  my @known=grep{$_ ne ''} map{normalise_name($_)}($row->{preferred_name},$row->{official_name},$row->{alternative_name});
  if($candidate ne ''){
    for my $known(@known){
      if($candidate eq $known){$name_score=20;last;}
      if(index($candidate,$known)>=0 || index($known,$candidate)>=0){$name_score=12 if $name_score<12;}
    }
  }
  if(contains_institution($row->{main_affiliation}) || contains_institution($row->{affiliation_organisation})){$affiliation_score=15;}
  if(($row->{employment_status}||'') eq 'active' && defined $row->{publication_year}){$timeline_score=10;}
  my $total=$identifier_score+$name_score+$affiliation_score+$timeline_score;
  my($decision,$review_status);
  if($identifier_score==55 || $total>=80){$decision='confirmed';$review_status='auto_confirmed';$confirmed++;}
  else {$decision='review';$review_status='needs_review';$reviewed++;}
  next if ($row->{review_status}||'') eq 'manually_rejected' || ($row->{review_status}||'') eq 'manually_confirmed';

  $dbh->do(q{
    UPDATE researcher_publication_links
    SET match_score=?,
        system_decision=?,
        review_status=?,
        affiliation_status=CASE
          WHEN ? > 0 THEN 'institution_affiliation_match'
          WHEN affiliation_status='confirmed' THEN affiliation_status
          ELSE 'affiliation_not_confirmed'
        END,
        last_confirmed_at=NOW()
    WHERE id=?
  },undef,$total,$decision,$review_status,$affiliation_score,$row->{id});

  if($decision eq 'review'){
    my($exists)=$dbh->selectrow_array(q{
      SELECT COUNT(*) FROM researcher_disambiguation_cases
      WHERE borrowernumber=? AND publication_id=? AND source_name=? AND review_status IN ('pending','needs_review','unreviewed')
    },undef,$row->{borrowernumber},$row->{publication_id},$row->{source_name});
    unless($exists){
      $dbh->do(q{
        INSERT INTO researcher_disambiguation_cases
        (borrowernumber,publication_id,source_name,source_author_id,candidate_name,candidate_affiliation,identifier_score,name_score,affiliation_score,timeline_score,total_score,system_decision,review_status,evidence_json)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      },undef,$row->{borrowernumber},$row->{publication_id},$row->{source_name},$source_author_id,$row->{author_name},$row->{main_affiliation},$identifier_score,$name_score,$affiliation_score,$timeline_score,$total,$decision,$review_status,'{}');
    }
  }
}
print "confirmed=$confirmed review=$reviewed rejected=$rejected
";
