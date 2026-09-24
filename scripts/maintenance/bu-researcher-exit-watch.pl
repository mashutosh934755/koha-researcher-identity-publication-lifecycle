#!/usr/bin/perl
use Modern::Perl;
use C4::Context;
my $dbh=C4::Context->dbh;
my $candidates=$dbh->selectall_arrayref(q{
SELECT c.borrowernumber,c.preferred_name,c.user_type,c.employment_status,c.verification_status,c.sync_enabled,
       b.cardnumber,b.dateexpiry,b.lost,b.gonenoaddress,b.debarred
FROM custom_profile_details c
JOIN borrowers b ON b.borrowernumber=c.borrowernumber
WHERE c.employment_status='active'
  AND (b.dateexpiry<CURDATE() OR COALESCE(b.lost,0)<>0 OR COALESCE(b.gonenoaddress,0)<>0)
ORDER BY b.dateexpiry ASC
},{Slice=>{}})||[];
print "RESEARCHER EXIT / NO-DUES CANDIDATE REPORT
";
if(!@$candidates){print "No exit candidates detected.
"; exit 0;}
for my $row(@$candidates){
 print join(' | ','EXIT_CANDIDATE','borrowernumber='.($row->{borrowernumber}//''),'name='.($row->{preferred_name}//''),'user_type='.($row->{user_type}//''),'expiry='.($row->{dateexpiry}//''),'lost='.($row->{lost}//0),'gone_no_address='.($row->{gonenoaddress}//0))."
";
 my $exists=$dbh->selectrow_array(q{SELECT COUNT(*) FROM researcher_audit_log WHERE borrowernumber=? AND action_type='exit_candidate_detected' AND created_at>=DATE_SUB(NOW(),INTERVAL 7 DAY)},undef,$row->{borrowernumber})||0;
 if(!$exists){
  $dbh->do(q{INSERT INTO researcher_audit_log (borrowernumber,action_type,new_value,action_reason,source) VALUES (?,'exit_candidate_detected',?,'Patron account status requires manual no-dues or exit review','exit-watcher')},undef,$row->{borrowernumber},join('; ','dateexpiry='.($row->{dateexpiry}//''),'lost='.($row->{lost}//0),'gonenoaddress='.($row->{gonenoaddress}//0)));
 }
}
print "Manual action required in Researcher Verification Dashboard.
No profile was automatically marked Former.
";
