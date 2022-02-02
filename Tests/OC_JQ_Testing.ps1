using namespace System.Collections.Generic
using namespace System.Diagnostics


write-host "OC JQ Performance Tester Script"
write-host "----------------------------------------"
write-host "Version: 0.5"
write-host "Author: Eric Hart"
write-host "Contact: Eric.Hart@logrhythm.com"
write-host "----------------------------------------"
write-host "This script will submit batches of 50,000 logs to Webhook Beat."
write-host "This leverages the custom augmentation Source Defined Parser and "
write-host "emulates the behavior of common log sources. "
write-host ""
write-host "This leverages the same JQ method for adding metadata fields as LR Released JQ Pipelines."
write-host "This test will iterate through batch sizes that contain specific byte size payloads for the"
write-host "subject field to showcase the impact of field size."
write-host ""
write-host "All messages are effectively the same exact message with the exception of the incrementation"
write-host "of the size of the subject field."
write-host ""
write-host "This demonstrates the core issue with the add_field jq function and its impact when"
write-host "working with larger data sizes."
$Params = @{
    Uri = 'http://172.17.5.20:8085/webhook'
    Method = 'post'
    TimeoutSec = 300
    MaximumRetryCount = 5
    RetryIntervalSec = 1
    ErrorAction = 'SilentlyContinue'
}


$MaxMsgs = 50000


#Source: http://gallery.technet.microsoft.com/scriptcenter/Invoke-Async-Allows-you-to-83b0c9f0#content
 
function Invoke-Async{
    param(
    #The data group to process, such as server names.
    [parameter(Mandatory=$true, ValueFromPipeLine=$true)]
    [object[]]$Set,
    #The parameter name that the set belongs to, such as Computername.
    [parameter(Mandatory=$true)]
    [string] $SetParam,
    #The Cmdlet for Function you'd like to process with.
    [parameter(Mandatory=$true, ParameterSetName='cmdlet')]
    [string]$Cmdlet,
    #The ScriptBlock you'd like to process with
    [parameter(Mandatory=$true, ParameterSetName='ScriptBlock')]
    [scriptblock]$ScriptBlock,
    #any aditional parameters to be forwarded to the cmdlet/function/scriptblock
    [hashtable]$Params,
    #number of jobs to spin up, default being 10.
    [int]$ThreadCount=20,
    #return performance data
    [switch]$Measure,
    #return abort threshold (if non-negative/non-zero, bails after this many errors have occured)
    [int]$AbortAfterErrorCount=-1
    )
    Begin {
        [int] $ErrorCounter = 0                                                                              #20141031 Jana - Added to track errors and bail
        [int] $AllowedErrorCount = if ($AbortAfterErrorCount -le 0) {9999999} else {$AbortAfterErrorCount}   #20141031 Jana - Added to track errors and bail
        $Threads = @()
        $Length = $JobsLeft = $Set.Length
     
        $Count = 0
        if($Length -lt $ThreadCount){$ThreadCount=$Length}
        $Jobs = @(1..$ThreadCount  | ForEach-Object{$null})
     
        If($PSCmdlet.ParameterSetName -eq 'cmdlet') {
            $CmdType = (Get-Command $Cmdlet).CommandType
            if($CmdType -eq 'Alias') {
                $CmdType = (Get-Command (Get-Command $Cmdlet).ResolvedCommandName).CommandType
            }
     
            If($CmdType -eq 'Function') {
                $ScriptBlock = (Get-Item Function:\$Cmdlet).ScriptBlock
                1..$ThreadCount | ForEach-Object{ $Threads += [powershell]::Create().AddScript($ScriptBlock)}
            }
            ElseIf($CmdType -eq "Cmdlet") {
                1..$ThreadCount  | ForEach-Object{ $Threads += [powershell]::Create().AddCommand($Cmdlet)}
            }
        }
        Else {
            1..$ThreadCount | ForEach-Object{ $Threads += [powershell]::Create().AddScript($ScriptBlock)}
        }
     
        If($Params){$Threads | ForEach-Object{$_.AddParameters($Params) | Out-Null}}
     
    }
    Process {
        while($JobsLeft) {
        
            #20140929 Jana - Bug fix - Changed "-lt" to "-le" because it does not execute if if there is only 1 item in the set total to begin with!
            #for($idx = 0; $idx -lt ($ThreadCount-1) ; $idx++)
            for($idx = 0; $idx -le ($ThreadCount-1) ; $idx++) {
     
                $SetParamObj = $Threads[$idx].Commands.Commands[0].Parameters| Where-Object {$_.Name -eq $SetParam}
     
                #NOTE: Only hits this block after atleast one item has been kicked off..so during very first pass, skips this.
                If ($Jobs[$idx] -ne $null) {
                    #job ran ok, clear it out
                    If($Jobs[$idx].IsCompleted) {
                        $result = $null
                        if($threads[$idx].InvocationStateInfo.State -eq "Failed") {
                            $result  = $Threads[$idx].InvocationStateInfo.Reason
     
                            #Will write out the hashtable values in the error instead of "Set Item: System.Collections.Hashtable Exception: ...."
                            $OutError = "Set Item: $($($SetParamObj.Value)| Out-String )"
                            Write-Error "$OutError Exception: $result"
     
                            #Write-Error "Set Item: $($SetParamObj.Value) Exception: $result"
     
                            #This was the original code by the original author (always leave this commented)
                            #Write-Error "Set Item: $($SetParamObj) Exception: $result"
     
                            #20141031 Jana - Added to track errors and bail
                            $ErrorCounter++
                            if ($ErrorCounter -ge $AllowedErrorCount) {
                                break;
                            }
                        }
                        else {
                            $result = $Threads[$idx].EndInvoke($Jobs[$idx])
                        }
                        $Jobs[$idx] = $null
                        $JobsLeft-- #one less left
     
                        write-verbose "Completed: $($SetParamObj.Value)"
                        #write-verbose "Completed: $SetParamObj in $ts"
                        #write-progress -Activity "Processing Set" -Status "$JobsLeft jobs left" -PercentComplete (($length-$jobsleft)/$length*100)
                    }
                }

                #add job if there is more to process
                If(($Count -lt $Length) -and ($Jobs[$idx] -eq $null)) {
                    write-verbose "starting: $($Set[$Count])"
                    $Threads[$idx].Commands.Commands[0].Parameters.Remove($SetParamObj) | Out-Null #check for success?
                    $Threads[$idx].AddParameter($SetParam,$Set[$Count]) | Out-Null
                    $Jobs[$idx] = $Threads[$idx].BeginInvoke()
                    $Count++
                }
            }
     
            #20141031 Jana - Added to track errors and bail
            if ($ErrorCounter -ge $AllowedErrorCount) {
                break;
            }
        }
    }
    End {
        $Threads | ForEach-Object{$_.runspace.close();$_.Dispose()}
    }
}


For ($a = 0; $a -le 8; $a++) {
    switch ($a) {
        0 {
            write-host "$(Get-Date) - OC JQ Test - Field Containing = 7 bytes"
            # 7
            $MsgSize = "7 Bytes"
            $OGMessage = '{"i":1}'
            break;
        }
        
        1 { 
            write-host "$(Get-Date) - OC JQ Test - Field Containing = 88 bytes"
            # 88 bytes
            $MsgSize = "88 Bytes"
            $OGMessage = 'c:\program files (x86)\common files\trophy\services\taskqueue\panel\taskqueuepanel.exe'
            break;
        }

        # 122 Bytes
        2 {
            write-host "$(Get-Date) - OC JQ Test - Field Containing = 122 bytes"
            $MsgSize = "122 Bytes"
            $OGMEssage = 'c:\windows\system32\cmd.exe /c driverquery.exe /v /fo csv > "c:\program files\hewlett-packard\ams\service\driverslist.csv"'
            break;
        }
        3 {
            write-host "$(Get-Date) - OC JQ Test - Field Containing = 290 bytes"
            # 500 characters
            $MsgSize = "290 Bytes"
            $OGMessage = 'tableau.exe -t bbbbbblapp01p 11.13 -1 -c ";d:\program files\tableau\tableau server\9.1\bin\tableau.lic;" -lmgrd_port 6978 -srv bbbbbbbbbbbbbbbbbbbbbjt2a7201a223kntsjsujd2wkjr0jpo7ry56bbbbbbbb --lmgrd_start bbbbbbbb -vdrestart 0 -l "d:\program files\tableau\tableau server\logs\tablicsrv.log"'
            break;
        }
        4 {
            write-host "$(Get-Date) - OC JQ Test - Field Containing = 758 bytes"
            $MsgSize = "758 Bytes"
            $OGMessage = '.\jre\6.0/bin/java.exe -xmx2048m -xms2048m -xgcpolicy:gencon -xcompressedrefs -xdump:heap+system:none -xdump:system:events=gpf+abort,range=1..2,request=serial+compact+prepwalk -xdump:system:events=systhrow+throw,filter=java/lang/outofmemory*,range=1..2,request=serial+compact+prepwalk "-cp" "../tomcat/bin/bootstrap.jar;.\jre\6.0/lib/tools.jar" "-dcom.ibm.cognos.disp.usedaemonthreads=true" "-dcatalina.base=../tomcat" "-dcatalina.home=../tomcat" "-djava.util.logging.manager=org.apache.juli.classloaderlogmanager" "-djava.util.logging.config.file=../tomcat/conf/logging.properties" "-djava.io.tmpdir=..\bin64\../temp" "-djava.endorsed.dirs=.\jre\6.0/lib/endorsed;.\jre\6.0/jre/lib/endorsed;../tomcat/lib/endorsed" org.apache.catalina.startup.bootstrap start'
            break;
        }
        5 {
            write-host "$(Get-Date) - OC JQ Test - Field Containing = 1331 bytes"
            # Very frequent
            $MsgSize = "1331 Bytes"
            $OGMessage = 'e:\emc\smas\jre\bin\java -d[server:server-0] -xms1024m -xmx12288m -dprogram.name=domain.bat "-dsun.rmi.dgc.client.gcinterval=3600000 -dsun.rmi.dgc.server.gcinterval=3600000 -djava.net.preferipv4stack=true" -djava.util.logging.manager=java.util.logging.logmanager -duser.language=en -djboss.modules.system.pkgs=org.jboss.byteman -dorg.jboss.resolver.warning=true -djava.library.path=e:\emc\smas\jboss\standalone\lib -xx:+useg1gc -xss1024k -djboss.as.management.blocking.timeout=3600 -xx:+printgcdetails -xx:+printgcapplicationstoppedtime -xx:+printgcapplicationconcurrenttime -xx:+printgcdatestamps -xloggc:gclog.log -xx:+usegclogfilerotation -xx:numberofgclogfiles=5 -xx:gclogfilesize=2000k -xx:+printtenuringdistribution -du4v_c7r_ser_codec=new -djava.net.preferipv4stack=true -djboss.bind.address.management=localhost -djboss.home.dir=e:\emc\smas\jboss -djboss.modules.system.pkgs=org.jboss.byteman -dsmas.persistence.type=hibernate -djboss.server.log.dir=e:\emc\smas\jboss\domain\servers\server-0\log -djboss.server.temp.dir=e:\emc\smas\jboss\domain\servers\server-0\tmp -djboss.server.data.dir=e:\emc\smas\jboss\domain\servers\server-0\data -dlogging.configuration=file:e:\emc\smas\jboss\domain\servers\server-0\data\logging.properties -jar e:\emc\smas\jboss\jboss-modules.jar -mp e:\emc\smas\jboss\modules org.jboss.as.server'
            break;
        }
        6 {
            write-host "$(Get-Date) - OC JQ Test - Field Containing = 1553 bytes"
            # Uncommon
            $MsgSize = "1553 Bytes"
            $OGMessage = '"c:\program files (x86)\microsoft\edge\application\msedge.exe" --winrt-background-task-event=bbbbbbbberdvrainvh22zu3vehmkd3dlyl9wbbbbbbbbawvudbaagp0ickndz2rfwldaagrxedbfqufzmklhc3z2bbbbbbbbqvegahr0chm6ly9hchbses5zdgfydgfjyxjlzxj0b2rhes5jb20veryh2oqbr2ioyrrovsxngbxbyaaaeabbbplydnbuc5qipx2q5buo+dc3y2c8umvuqwzlhjjcc3tixc8qibp5umpcwvvow5lnwmpx04r2ebst4nh/gd2jvki4kv4fsv/lw+hkomb00nn0sb8f5ffymjgk6kgkmerl7osajnlt7acat8phsu/wqaofzvukhgw5mfad9hlmk9tlldxqunhwtumf11wukgye7hc9qzjeacqabpq4qha8tz7hn97lihsxjarrmoo+phf/unk8z60gcfhmyhbuensneitccsdcswzmf4s2vy4dndu336zcw4/3x83o4/dyu623acts/lfca5vbyv1abedymbtgkk+0zixc48gp7utnb0+dwv6oyff9ldcuilfn2rojm7fclrn0izwrwtq3jylc/spkn2gmxbbbbbbbbhce2ditny6usqvmr4i+txohv21ump8kfb6gjwcc2l/od/6k79onzopfc83qkbc29uqvtokvg12tthyzbzypzaddgmkus7jrv4lc1emnjj/zhisc7bilwvdhmumsv43/gbyadcylob1gql0m9zvslf8etj+bimnx7+i/vjg6gvp8ttvsqth5tmcx/u3heabvpuxq4n6zk+9wgzbshhi5xntqkecemeyhaexpjwzp1bfry5epjqwnimlohrhkegvylfob3vvnuopi49meq0wlgnpltrgfbe6hj5gqgb+gindzqy+ijfmpfv3gtzvbyylez/z+uw9bbbbbbbbuhtwn66hk19pxosdna0auirdgeb3j8eqhq6h1rfgejidxhnfgz1q6vzrzmrm12+au2vdnub1wtqcjanuaq1y85961+xriytvk4+dfr8xn7tx0qg0plzfqzq95rxntl1adcz5a6itxb3pwfurunqpjluqi4c6a5ny9w3kjdtyleoy3glkgxax5l93xwnidmfv9togljfsk3bqsafvhfbdxt3fxr7+kiobbbbbbbbyz62jlu2najr9xan5m1ytjizq1l+cmjebnhxohcfpjepfg9q0meuaejcssm84sb91asddznaqisyieo5ktjvjqay5pmtnrjr5vwyioz5/ovo8z0sl0/kn/1kivjvjids+hx6wxr5w7glfxya1t6uxi9oy9vfqpwi5grirvniglkggf60qjz1r6zpyvamaotp0qnsi9ndc8fhjnl7evx3amei4ubbbbbbbb5km9pfyjod+senjub9ywkrneop4vhrx91hpbq0tbbbbbbbbahqoqy29udgvudc1lbmnvzgluzxijywvzmti4z2nt'
            break;
        }
        7 {
            # Fairly frequent
            write-host "$(Get-Date) - OC JQ Test - Field Containing = 1631 bytes"
            $MsgSize = '1631 Bytes'
            $OGMessage = '/u02/em13c/middleware/oracle_common/jdk/bin/java -djava.security.egd=file:///dev/./urandom -dweblogic.security.ssl.enablejsse=true -server -xms32m -xmx200m -djdk.tls.ephemeraldhkeysize=2048 -dweblogic.rootdirectory=/u02/em13c/oms_inst/user_projects/domains/gcdomain/nodemanager -dcoherence.home=/u02/em13c/middleware/wlserver/../coherence -dbea.home=/u02/em13c/middleware/wlserver/.. -dohs.product.home=/u02/em13c/middleware/ohs -dlistenaddress=bbbbbbbbbbbb.bbbbbb.ad -dnodemanagerhome=/u02/em13c/oms_inst/user_projects/domains/gcdomain/nodemanager -dstartscriptname=startemserver.sh -dstartscriptenabled=true -dusekssfordemo=false -bbuitenabled=true -dlistenport=7403 -dweblogic.rootdirectory=/u02/em13c/oms_inst/user_projects/domains/gcdomain -doracle.security.jps.config=/u02/em13c/oms_inst/user_projects/domains/gcdomain/config/fmwconfig/jps-config-jse.xml -dcommon.components.home=/u02/em13c/middleware/oracle_common -dopss.version=12.2.1.3 -dweblogic.rootdirectory=/u02/em13c/oms_inst/user_projects/domains/gcdomain -doracle.bi.home.dir=/u02/em13c/middleware/bi -doracle.bi.config.dir=/u02/em13c/oms_inst/user_projects/domains/gcdomain/config/fmwconfig/biconfig -doracle.bi.environment.dir=/u02/em13c/oms_inst/user_projects/domains/gcdomain/config/fmwconfig/bienv -doracle.bi.12c=true -ddomain.home=/u02/em13c/oms_inst/user_projects/domains/gcdomain -dfile.encoding=utf-8 -djava.system.class.loader=com.oracle.classloader.weblogic.launchclassloader -djava.security.policy=/u02/em13c/middleware/wlserver/server/lib/weblogic.policy -dweblogic.nodemanager.javahome=/u02/em13c/middleware/oracle_common/jdk weblogic.nodemanager -v'
            break;
        }
        8 {
            write-host "$(Get-Date) - OC JQ Test - Field Containing = 2223 Bytes"
            $MsgSize = '2223 Bytes'
            $OGMessage = '"c:\program files (x86)\microsoft\edgeupdate\microsoftedgeupdate.exe" /ping pd94bwwgdmvyc2lvbj0ims4bbbbbbbbvzgluzz0ivvrgltgipz48cmvxdwvzdcbwcm90b2nvbd0imy4wiib1cgrhdgvypsjpbwfoysigdxbkyxrlcnzlcnnpb249ijeumy4xntmuntuiihnozwxsx3zlcnnpb249ijeumy4xmjcumtuiiglzbwfjagluzt0imsigc2vzc2lvbmlkpsj7qku1mzq1mjctotfcoc00rue4ltlgn0mtmje2mty4njbequy3fsigdxnlcmlkpsj7nuy0njczrtetmtkwmy00ntlclthbqjitnkremzvdnbbyrjndfsigaw5zdgfsbhnvdxjjzt0ic2nozwr1bgvyiibyzxf1zxn0awq9interbbzmdhgrs0xnzq2ltqwodmtqjcyrc1bnzlgntixmdvemtj9iibkzwr1cd0iy3iiigrvbwfpbmpvaw5lzd0imsi-pgh3igxvz2ljywxfy3b1cz0incigcgh5c21lbw9yet0iocbbbbbbbb90exblpsiyiibzc2u9ijeiihnzzti9ijeiihnzztm9ijeiihnzc2uzpsixiibzc2u0mt0imsigc3nlndi9ijeiigf2ed0imsivpjxvcybwbgf0zm9ybt0id2luiib2zxbbbbbbbbixmc4wlje5mbbyljezndgiihnwpsiiigfyy2g9ing2ncivpjxvzw0gchjvzhvjdf9tyw51zmfjdhvyzxi9ikrlbgwgsw5jliigchjvzhvjdf9uyw1lpsjmyxrpdhvkzsbfntq0mcivpjxlehagzxrhzz0ijnf1b3q7cjbbbbbbbbsyvgdxl0hyemp2rk5cumhvcejxujlzympyehflvurioxvymd0mcxvvddsilz48yxbwigfwcglkpsj7rjnbbbbbbbbtruzens00mdncltk1njktmzk4qtiwrjfcqtrbfsigdmvyc2lvbj0ims4zlje1my41nsigbmv4dbbbbbbbb249iiigbgfuzz0iiibicmfuzd0ir0dmuyigy2xpzw50psiiigluc3rhbgxhz2u9iju2msigaw5zdgfsbgrhdgu9ijq5mjeiignvag9ydd0icnjmqdaumtaipjx1cgrhdgvjagvjay8-phbpbmcgcj0imsigcmq9iju0obbiihbpbmdfznjlc2huzxnzpsj7mdkzq0vfrjmtqti5nc00rjzelujfotktodrcqjazoty1ntdffsivpjwvyxbbbbbbbbbgyxbwawq9ins1nkvcmthgoc1cmda4ltrbbkqtqjzemi04qzk3rku3rtkwnjj9iib2zxbbbbbbbbi5ni4wljewntqunjiiig5lehr2zxbbbbbbbbiiigfwpsjzdgfibgutyxjjaf94njqiigxhbmc9iiigynjhbmq9ikddrvuiignsawvudd0iiiblehblcmltzw50cz0iy29uc2vudd1mywxzzsigaw5zdgfsbgfnzt0indeziibpbnn0ywxszgf0zt0intmzncigy29ob3j0psjycmzamc4xmcigbgfzdf9syxvuy2hfdgltzt0imtmyodu5nzyynzqymza2nteipjx1cgrhdgvjagvjay8-phbpbmcgywn0axzlpsixiibhpsixiibypsixiibhzd0intq4ncigcmq9iju0obbiihbpbmdfznjlc2huzxnzpsj7mbb5m0yznuetn0y5nc00odu3ltgwmuytmda3ruu5mtg3nje3fsivpjwvyxbbbbbbbbbgyxbwawq9intgmzaxnziyni1grtjbltqyotutoejeri0wmemzqtlbn0u0qzv9iib2zxbbbbbbbbi5ni4wljewntqunjiiig5lehr2zxbbbbbbbbiiigxhbmc9iiigynjhbmq9ikdhtfmiignsawvudd0iiibpbnn0ywxsywdlpsiyocigaw5zdgfsbgrhdgu9iju0ntmiignvag9ydd0icnjmqdaumdgipjx1cgrhdgvjagvjay8-phbpbmcgcj0imsigcmq9iju0obbiihbpbmdfznjlc2huzxnzpsj7qte1nzkynjgtmzjemy00m0m4ltk1rtutmurbqui2quzfquuyfsivpjwvyxbwpjwvcmvbbbbbbbb'
            break;
        }
        9 {
            # Largest rare
            write-host "$(Get-Date) - OC JQ Test - Field Containing = 12327 bytes"
            $MsgSize = "12327 Bytes"
            $OGMessage = '"jre\bin\java" -djava.util.logging.config.file=properties/glide.properties -dsun.net.maxdatagramsockets=65535 -dcom.sun.jndi.ldap.object.disableendpointidentification=true -djdk.lang.process.allowambiguouscommands=true -xx:+useparallelgc -xms10m -xmx1024m -djava.library.path="lib;lib/x86-64" -classpath "lib/fastinfoset.jar;lib/hdrhistogram.jar;lib/javaewah.jar;lib/accessors-smart.jar;lib/aggs-matrix-stats-client.jar;lib/amb-client.jar;lib/animal-sniffer-annotations.jar;lib/annotations.jar;lib/ant-launcher.jar;lib/ant.jar;lib/antlr-runtime.jar;lib/antlr.jar;lib/aopalliance.jar;lib/app-itapp-mid.jar;lib/asm-analysis.jar;lib/asm-commons.jar;lib/asm-tree.jar;lib/asm.jar;lib/avro-ipc.jar;lib/avro.jar;lib/aws-java-sdk-acm.jar;lib/aws-java-sdk-acmpca.jar;lib/aws-java-sdk-alexaforbusiness.jar;lib/aws-java-sdk-api-gateway.jar;lib/aws-java-sdk-applicationautoscaling.jar;lib/aws-java-sdk-appstream.jar;lib/aws-java-sdk-appsync.jar;lib/aws-java-sdk-athena.jar;lib/aws-java-sdk-autoscaling.jar;lib/aws-java-sdk-autoscalingplans.jar;lib/aws-java-sdk-batch.jar;lib/aws-java-sdk-budgets.jar;lib/aws-java-sdk-cloud9.jar;lib/aws-java-sdk-clouddirectory.jar;lib/aws-java-sdk-cloudformation.jar;lib/aws-java-sdk-cloudfront.jar;lib/aws-java-sdk-cloudhsm.jar;lib/aws-java-sdk-cloudhsmv2.jar;lib/aws-java-sdk-cloudsearch.jar;lib/aws-java-sdk-cloudtrail.jar;lib/aws-java-sdk-cloudwatch.jar;lib/aws-java-sdk-cloudwatchmetrics.jar;lib/aws-java-sdk-codebuild.jar;lib/aws-java-sdk-codecommit.jar;lib/aws-java-sdk-codedeploy.jar;lib/aws-java-sdk-codepipeline.jar;lib/aws-java-sdk-codestar.jar;lib/aws-java-sdk-cognitoidentity.jar;lib/aws-java-sdk-cognitoidp.jar;lib/aws-java-sdk-cognitosync.jar;lib/aws-java-sdk-comprehend.jar;lib/aws-java-sdk-config.jar;lib/aws-java-sdk-connect.jar;lib/aws-java-sdk-core.jar;lib/aws-java-sdk-costandusagereport.jar;lib/aws-java-sdk-costexplorer.jar;lib/aws-java-sdk-datapipeline.jar;lib/aws-java-sdk-dax.jar;lib/aws-java-sdk-devicefarm.jar;lib/aws-java-sdk-directconnect.jar;lib/aws-java-sdk-directory.jar;lib/aws-java-sdk-discovery.jar;lib/aws-java-sdk-dlm.jar;lib/aws-java-sdk-dms.jar;lib/aws-java-sdk-dynamodb.jar;lib/aws-java-sdk-ec2.jar;lib/aws-java-sdk-ecr.jar;lib/aws-java-sdk-ecs.jar;lib/aws-java-sdk-efs.jar;lib/aws-java-sdk-eks.jar;lib/aws-java-sdk-elasticache.jar;lib/aws-java-sdk-elasticbeanstalk.jar;lib/aws-java-sdk-elasticloadbalancing.jar;lib/aws-java-sdk-elasticloadbalancingv2.jar;lib/aws-java-sdk-elasticsearch.jar;lib/aws-java-sdk-elastictranscoder.jar;lib/aws-java-sdk-emr.jar;lib/aws-java-sdk-events.jar;lib/aws-java-sdk-fms.jar;lib/aws-java-sdk-gamelift.jar;lib/aws-java-sdk-glacier.jar;lib/aws-java-sdk-glue.jar;lib/aws-java-sdk-greengrass.jar;lib/aws-java-sdk-guardduty.jar;lib/aws-java-sdk-health.jar;lib/aws-java-sdk-iam.jar;lib/aws-java-sdk-importexport.jar;lib/aws-java-sdk-inspector.jar;lib/aws-java-sdk-iot1clickdevices.jar;lib/aws-java-sdk-iot1clickprojects.jar;lib/aws-java-sdk-iot.jar;lib/aws-java-sdk-iotanalytics.jar;lib/aws-java-sdk-iotjobsdataplane.jar;lib/aws-java-sdk-kinesis.jar;lib/aws-java-sdk-kinesisvideo.jar;lib/aws-java-sdk-kms.jar;lib/aws-java-sdk-lambda.jar;lib/aws-java-sdk-lex.jar;lib/aws-java-sdk-lexmodelbuilding.jar;lib/aws-java-sdk-lightsail.jar;lib/aws-java-sdk-logs.jar;lib/aws-java-sdk-machinelearning.jar;lib/aws-java-sdk-macie.jar;lib/aws-java-sdk-marketplacecommerceanalytics.jar;lib/aws-java-sdk-marketplaceentitlement.jar;lib/aws-java-sdk-marketplacemeteringservice.jar;lib/aws-java-sdk-mechanicalturkrequester.jar;lib/aws-java-sdk-mediaconvert.jar;lib/aws-java-sdk-medialive.jar;lib/aws-java-sdk-mediapackage.jar;lib/aws-java-sdk-mediastore.jar;lib/aws-java-sdk-mediastoredata.jar;lib/aws-java-sdk-mediatailor.jar;lib/aws-java-sdk-migrationhub.jar;lib/aws-java-sdk-mobile.jar;lib/aws-java-sdk-models.jar;lib/aws-java-sdk-mq.jar;lib/aws-java-sdk-neptune.jar;lib/aws-java-sdk-opsworks.jar;lib/aws-java-sdk-opsworkscm.jar;lib/aws-java-sdk-organizations.jar;lib/aws-java-sdk-pi.jar;lib/aws-java-sdk-pinpoint.jar;lib/aws-java-sdk-polly.jar;lib/aws-java-sdk-pricing.jar;lib/aws-java-sdk-rds.jar;lib/aws-java-sdk-redshift.jar;lib/aws-java-sdk-rekognition.jar;lib/aws-java-sdk-resourcegroups.jar;lib/aws-java-sdk-resourcegroupstaggingapi.jar;lib/aws-java-sdk-route53.jar;lib/aws-java-sdk-s3.jar;lib/aws-java-sdk-sagemaker.jar;lib/aws-java-sdk-sagemakerruntime.jar;lib/aws-java-sdk-secretsmanager.jar;lib/aws-java-sdk-serverlessapplicationrepository.jar;lib/aws-java-sdk-servermigration.jar;lib/aws-java-sdk-servicecatalog.jar;lib/aws-java-sdk-servicediscovery.jar;lib/aws-java-sdk-ses.jar;lib/aws-java-sdk-shield.jar;lib/aws-java-sdk-simpledb.jar;lib/aws-java-sdk-simpleworkflow.jar;lib/aws-java-sdk-snowball.jar;lib/aws-java-sdk-sns.jar;lib/aws-java-sdk-sqs.jar;lib/aws-java-sdk-ssm.jar;lib/aws-java-sdk-stepfunctions.jar;lib/aws-java-sdk-storagegateway.jar;lib/aws-java-sdk-sts.jar;lib/aws-java-sdk-support.jar;lib/aws-java-sdk-swf-libraries.jar;lib/aws-java-sdk-transcribe.jar;lib/aws-java-sdk-translate.jar;lib/aws-java-sdk-waf.jar;lib/aws-java-sdk-workdocs.jar;lib/aws-java-sdk-workmail.jar;lib/aws-java-sdk-workspaces.jar;lib/aws-java-sdk-xray.jar;lib/aws-java-sdk.jar;lib/aws-signing-request-interceptor.jar;lib/axiom-api.jar;lib/axiom-dom.jar;lib/axiom-impl.jar;lib/axis.jar;lib/bayeux-api.jar;lib/bc-fips.jar;lib/bcpkix-fips.jar;lib/cache-api.jar;lib/camel-core.jar;lib/checker-qual.jar;lib/cimiql.jar;lib/clotho-api.jar;lib/cometd-java-client.jar;lib/cometd-java-common.jar;lib/commons-beanutils.jar;lib/commons-cli.jar;lib/commons-codec.jar;lib/commons-collections4.jar;lib/commons-collections.jar;lib/commons-compress.jar;lib/commons-core-automation.jar;lib/commons-core.jar;lib/commons-csv.jar;lib/commons-exec.jar;lib/commons-glide.jar;lib/commons-httpclient.jar;lib/commons-io.jar;lib/commons-jxpath.jar;lib/commons-lang3.jar;lib/commons-lang.jar;lib/commons-logging.jar;lib/commons-math3.jar;lib/commons-net.jar;lib/commons-pool2.jar;lib/commons-process-flow.jar;lib/commons-vfs2.jar;lib/compiler.jar;lib/connector-blobstorage.jar;lib/connector-blockstorage.jar;lib/connector-cfgmgmt.jar;lib/connector-compute.jar;lib/connector-dto.jar;lib/connector-ipam.jar;lib/connector-loadbalancer.jar;lib/connector-network.jar;lib/connector-nodeaccess.jar;lib/connector-script.jar;lib/connector-ssh.jar;lib/connector-util.jar;lib/da-core.jar;lib/dist-upgrade-runner.jar;lib/dnsjava.jar;lib/dom4j.jar;lib/eddsa.jar;lib/ehcache.jar;lib/elasticsearch-cli.jar;lib/elasticsearch-core.jar;lib/elasticsearch-geo.jar;lib/elasticsearch-rest-client.jar;lib/elasticsearch-rest-high-level-client.jar;lib/elasticsearch-secure-sm.jar;lib/elasticsearch-x-content.jar;lib/elasticsearch.jar;lib/error_prone_annotations.jar;lib/failureaccess.jar;lib/flume-file-channel.jar;lib/flume-ng-auth.jar;lib/flume-ng-config-filter-api.jar;lib/flume-ng-configuration.jar;lib/flume-ng-core.jar;lib/flume-ng-sdk.jar;lib/ftp4che.jar;lib/glide-proxy-commons.jar;lib/grammatica.jar;lib/groovy-all.jar;lib/grpc-api.jar;lib/grpc-context.jar;lib/grpc-core.jar;lib/grpc-netty-shaded.jar;lib/grpc-protobuf-lite.jar;lib/grpc-protobuf.jar;lib/grpc-services.jar;lib/grpc-stub.jar;lib/gson.jar;lib/guava-retrying.jar;lib/guava.jar;lib/guice-assistedinject.jar;lib/guice-multibindings.jar;lib/guice.jar;lib/h2.jar;lib/hibernate-jpa-2.0-api.jar;lib/hppc.jar;lib/httpasyncclient.jar;lib/httpclient.jar;lib/httpcore-nio.jar;lib/httpcore.jar;lib/httpmime.jar;lib/ignite-core.jar;lib/ignite-shmem.jar;lib/ini4j.jar;lib/ion-java.jar;lib/istack-commons-runtime.jar;lib/itom-oi-metrics.jar;lib/itom-oi-models.jar;lib/j2objc-annotations.jar;lib/j2ssh-ant.jar;lib/j2ssh-common.jar;lib/j2ssh-core.jar;lib/j2ssh-daemon.jar;lib/jackson-annotations.jar;lib/jackson-core-asl.jar;lib/jackson-core.jar;lib/jackson-databind.jar;lib/jackson-dataformat-cbor.jar;lib/jackson-dataformat-smile.jar;lib/jackson-dataformat-yaml.jar;lib/jackson-jaxrs.jar;lib/jackson-mapper-asl.jar;lib/jackson-module-afterburner.jar;lib/jackson-xc.jar;lib/jakarta-oro.jar;lib/jakarta.activation-api.jar;lib/jakarta.activation.jar;lib/jakarta.mail.jar;lib/jakarta.xml.bind-api.jar;lib/jasypt.jar;lib/java-service-wrapper.jar;lib/java-sizeof.jar;lib/javassist.jar;lib/javax-websocket-client-impl.jar;lib/javax-websocket-server-impl.jar;lib/javax.annotation-api.jar;lib/javax.inject.jar;lib/javax.json.jar;lib/javax.servlet-api.jar;lib/javax.websocket-api.jar;lib/javax.websocket-client-api.jar;lib/javax.xml.soap-api.jar;lib/jaxb-runtime.jar;lib/jaxen.jar;lib/jdom.jar;lib/jersey-bundle.jar;lib/jersey-core.jar;lib/jersey-server.jar;lib/jest-common.jar;lib/jest.jar;lib/jetty-annotations.jar;lib/jetty-client.jar;lib/jetty-http.jar;lib/jetty-io.jar;lib/jetty-jmx.jar;lib/jetty-jndi.jar;lib/jetty-plus.jar;lib/jetty-security.jar;lib/jetty-server.jar;lib/jetty-servlet.jar;lib/jetty-util-ajax.jar;lib/jetty-util.jar;lib/jetty-webapp.jar;lib/jetty-xml.jar;lib/jgrapht-core.jar;lib/jheaps.jar;lib/jmespath-java.jar;lib/jms.jar;lib/jmxremote.jar;lib/jmxremote_optional.jar;lib/jmxri.jar;lib/jna-platform.jar;lib/jna.jar;lib/joda-time.jar;lib/joesnmp.jar;lib/jopt-simple.jar;lib/jsch.jar;lib/jslp.jar;lib/json-path.jar;lib/json-smart.jar;lib/json.jar;lib/jsoup.jar;lib/jsr305.jar;lib/jsr311-api.jar;lib/jtidy.jar;lib/junixsocket-common.jar;lib/junixsocket-native-common.jar;lib/jzlib.jar;lib/lang-mustache-client.jar;lib/lbfgs4j.jar;lib/ldapbp.jar;lib/listenablefuture.jar;lib/log4j-api.jar;lib/log4j-core.jar;lib/log4j-over-slf4j.jar;lib/log4j-slf4j-impl.jar;lib/lombok.jar;lib/lucene-analyzers-common.jar;lib/lucene-backward-codecs.jar;lib/lucene-core.jar;lib/lucene-grouping.jar;lib/lucene-highlighter.jar;lib/lucene-join.jar;lib/lucene-memory.jar;lib/lucene-misc.jar;lib/lucene-queries.jar;lib/lucene-queryparser.jar;lib/lucene-sandbox.jar;lib/lucene-spatial3d.jar;lib/lucene-spatial-extras.jar;lib/lucene-spatial.jar;lib/lucene-suggest.jar;lib/manageontap.jar;lib/mapdb.jar;lib/mariadb-java-client.jar;lib/maverick-all.jar;lib/metrics-core.jar;lib/metrics-graphite.jar;lib/mibble-mibs.jar;lib/mibble-parser.jar;lib/mid-acc-commons.jar;lib/mid-analytics-common.jar;lib/mid-analytics.jar;lib/mid-events.jar;lib/mid-ih-usage-tracking.jar;lib/mid-installer.jar;lib/mid-loom.jar;lib/mid-metric-connector.jar;lib/mid-metrics.jar;lib/mid-monitoring.jar;lib/mid-web-server.jar;lib/mid.jar;lib/mimepull.jar;lib/mina-core.jar;lib/mssql-jdbc.jar;lib/native-lib-loader.jar;lib/ndl-grammar.jar;lib/netty-buffer.jar;lib/netty-codec-http.jar;lib/netty-codec.jar;lib/netty-common.jar;lib/netty-handler.jar;lib/netty-resolver.jar;lib/netty-tcnative-boringssl-static.jar;lib/netty-transport.jar;lib/occultus-commons.jar;lib/ognl.jar;lib/ojdbc8.jar;lib/org.dom4j.dom4j.jar;lib/org.eclipse.jgit.jar;lib/oro.jar;lib/oshi-core.jar;lib/owasp-java-html-sanitizer.jar;lib/parent-join-client.jar;lib/perfmark-api.jar;lib/process-flow-core.jar;lib/proto-google-common-protos.jar;lib/protobuf-java-util.jar;lib/protobuf-java.jar;lib/rank-eval-client.jar;lib/reflections.jar;lib/rhino-ng.jar;lib/rhino-script-evaluator.jar;lib/rmissl.jar;lib/sa-commons-mid.jar;lib/saaj-impl.jar;lib/slf4j-api.jar;lib/slp.jar;lib/snakeyaml.jar;lib/snappy-java.jar;lib/snc-automation-api.jar;lib/snc-xslt.jar;lib/snmp4j.jar;lib/snxpath.jar;lib/ssh.jar;lib/stax2-api.jar;lib/stax-api.jar;lib/stax-ex.jar;lib/stl-decomp-4j.jar;lib/stringtemplate.jar;lib/t-digest.jar;lib/thymeleaf.jar;lib/txw2.jar;lib/unbescape.jar;lib/uuid.jar;lib/validation-api.jar;lib/velocity-engine-core.jar;lib/websocket-api.jar;lib/websocket-client.jar;lib/websocket-common.jar;lib/websocket-server.jar;lib/websocket-servlet.jar;lib/windpapi4j.jar;lib/woodstox-core.jar;lib/wsdl4j.jar;lib/wss4j-ws-security-common.jar;lib/wss4j-ws-security-dom.jar;lib/xalan.jar;lib/xercesimpl.jar;lib/xml-apis.jar;lib/xmlbeans.jar;lib/xmlsec.jar;lib/xom.jar;lib/xtext-deps.jar;lib/yavijava.jar;lib/zstd-jni.jar;extlib/joda-time-2.9.2.jar" -dwrapper.key="qib62gdn8seb7tjmbzrdhmonf6q5rjnc" -dwrapper.port=32000 -dwrapper.jvm.port.min=31000 -dwrapper.jvm.port.max=31999 -dwrapper.pid=1908 -dwrapper.version="3.5.40-st" -dwrapper.native_library="wrapper" -dwrapper.arch="x86" -dwrapper.service="true" -dwrapper.cpu.timeout="10" -dwrapper.jvmid=1 -dwrapper.lang.domain="wrapper" -dwrapper.lang.folder="../lang" org.tanukisoftware.wrapper.wrapperstartstopapp com.service_now.mid.main 1 start com.service_now.mid.main true 1 stop --'
            break;
        }
        10 {
            # Largest observed Field Size
            write-host "$(Get-Date) - OC JQ Test - Field Containing = 17953 bytes"
            $MsgSize = "17953 Bytes"
            $OGMessage = '"d:\program files\ibm\cognos\c10_64\bin64\jre\6.0\bin\java.exe" -xms1024m -xmx1024m -xmnx512m -server -xgcpolicy:gencon -xdisableexplicitgc -xcompressedrefs "-dcubingservices_home=d:/program files/ibm/cognos/c10_64/v5dataserver" -dparentprocessport=49273 "-dcog_root=d:/program files/ibm/cognos/c10_64" "-djava.library.path=d:/program files/ibm/cognos/c10_64/bin64;" -classpath "d:/program files/ibm/cognos/c10_64/webapps/p2pd/web-inf/classes;d:/program files/ibm/cognos/c10_64/temp/xqe/classes;d:\program files\ibm\cognos\c10_64\v5dataserver\lib\commons-logging-1.0.4.jar;d:\program files\ibm\cognos\c10_64\v5dataserver\lib\commons-logging-api-1.0.3.jar;d:\program files\ibm\cognos\c10_64\v5dataserver\lib\dscommon.jar;d:\program files\ibm\cognos\c10_64\v5dataserver\lib\dwelogcore.jar;d:\program files\ibm\cognos\c10_64\v5dataserver\lib\jndiprovider.jar;d:\program files\ibm\cognos\c10_64\v5dataserver\lib\jndirepos.jar;d:\program files\ibm\cognos\c10_64\v5dataserver\lib\sqljdbc4.jar;d:\program files\ibm\cognos\c10_64\v5dataserver\lib\xml.jar;d:\program files\ibm\cognos\c10_64\v5dataserver\lib\ext\udf.jar;d:\program files\ibm\cognos\c10_64\v5dataserver\lib\ext\xqeudf.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\activation.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\activemq-core-4.1.2.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\activemq-jaas-4.1.2.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\agentservice.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\agentstudio.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\ags.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\an_dlt.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\apache-activemq-4.1.2.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\axis.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\axiscrnpclient.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\bcprov-jdk14-145.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cacheservice.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\caf.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\camaaa_acm.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\camaaa_cmbridge.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\camaaa_customjava.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\camaaa_framework.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\camaaa_ldap.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\camaaa_legacynamespace.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\camaaa_sdk.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\camaaa_srvc.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cam_aaa.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cam_aaa_configtest.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cam_aaa_customif.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cam_aaa_customproxy.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\castor-0.9.5.4.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cclcfgapi.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cclcoreutil.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\ccs.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cgs.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cgsjava.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cgsservice.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cmarchiving.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cmclient.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cmis-xmlbeans.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cmis.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cmutils.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cogadmin-templates.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cogadmin.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cogadminui-templates.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cogadminui.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cogatom.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\coglogging.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cognos-ws-ht.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cognosccl4j.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cognoscm.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cognoscmderby.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cognoscmintegrationcmis.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cognoscmintegrationfilesystem.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cognoscmplugin.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cognosipf.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cognosrepositoryapi.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\com.ibm.cognos.bux.handler.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\com.ibm.cognos.bux.lc.handler.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\com.ibm.cognos.bux.osgibridge.delegate.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\com.ibm.cognos.bux.osgibridge.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\com.ibm.cognos.bux.platform.helpers.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\commons-codec-1.3.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\commons-collections-3.2.1.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\commons-configuration-1.5.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\commons-discovery-0.2.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\commons-httpclient-3.1.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\commons-io-1.3.1.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\commons-lang-2.3.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\commons-logging-1.1.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\commons-logging-adapters-1.1.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\commons-logging-api-1.1.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\commons-pool-1.3.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\compiledjsps.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\concurrent.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cps-auth.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cps-consumer-common.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cps-producer-templates.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cps-producer.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\cps-services.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\csn.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\delivery.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\derbyclient.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\dimensionmanagementservice.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\dispatcherjsp.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\dlt.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\dom4j-1.6.1.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\drill.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\drillext.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\ehcache-core-2.2.0.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\fontbox-0.1.0.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\geronimo-jpa_3.0_spec-1.0.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\geronimo-jta_1.1_spec-1.1.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\hessian-3.0.8.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\hts.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\i18nj.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\icu4j-charsets.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\icu4j.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\ilel-category.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\ilel-collector.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\ilel-core.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\ilel-facet.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\ilel-markup.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\ilel-newton.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\ilel-numeric.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\ilel-security.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\ilel-sqp.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\ilel-util.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\j2html.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\jakarta-oro-2.0.8.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\jaxen-1.1.1.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\jaxrpc.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\jcam_autoca.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\jcam_autocafnd.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\jcam_crypto.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\jdxslt.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\jfst.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\jobs.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\jsds.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\jsm-common.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\json4j.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\jsqlconnect.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\jsr173_1.0_api.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\jython.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\log4j-1.2.8.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\logkit-1.2.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\logsv.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\lucene-core-2.4.1.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\mail.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\metadataservice.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\mfw.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\mfw4j.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\mfwa4j.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\mime4j-0.2.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\mx4j-tools.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\noticecast.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\ombridge.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\openjpa-1.2.1.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\p2pd.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\pdccore.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\pdcserver.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\pdfbox-0.7.3.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\pf.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\poi-3.6-20091214.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\poi-ooxml-3.6-20091214.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\poi-ooxml-schemas-3.6-20091214.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\portal.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\qfwv4tov5j.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\qnameimpl.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\qs.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\rdsclient.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\relmd.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\repositoryservice.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\resolver.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\rsupgrade.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\saaj.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\saprfcjni.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\securejson.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\serializer.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\serp-1.13.1.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\skintool.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\slf4j-api-1.6.0.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\slf4j-nop-1.6.0.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\snmp.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\soap.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\sps.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\stax-api-1.0.1.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\tagsoup-1.2.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\tds.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\uima-core.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\url2soap.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\user-pf.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\validator.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\velocity-1.1.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\viewer.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\wsdl4j-1.5.1.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\wsif.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\wstx-asl-3.2.5.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xalan.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xbean.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xbean_xpath.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xercesimpl.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xindice-1.1.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xml-apis.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xmlbeans-qname.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xmlpublic.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xmlsec-1.4.1.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xqeessbase.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xqemdds.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xqemonterey.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xqeodbo.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xqeodpcommon.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xqerolap.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xqesapjco.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xqeservice.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xqexml.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xqexmla.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xts.jar;d:\program files\ibm\cognos\c10_64\webapps\p2pd\web-inf\lib\xtsext.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\activation.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\annotations-api.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\catalina-ant.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\catalina-ha.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\catalina-tribes.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\catalina.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\cclcfgapi.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\cognosipf.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\dom4j-1.6.1.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\ecj-3.7.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\el-api.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\jasper-el.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\jasper-jdt.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\jasper.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\jaxen-1.1.1.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\jcam_crypto.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\jcam_jni.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\jsp-api.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\log4j-1.2.8.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\mail.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\servlet-api.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\tomcat-coyote.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\tomcat-dbcp.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\tomcat-i18n-es.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\tomcat-i18n-fr.jar;d:\program files\ibm\cognos\c10_64\tomcat\lib\tomcat-i18n-ja.jar;" -bbuerycontextfactoryimpl=com.cognos.xqe.runtree.olap.mdx.interpreter.xqequerycontextfactoryimpl -dcommonclassesfactoryimpl=com.cognos.xqe.cubingservices.xqecommonclassesfactory -duseconnection4requestid -dignore_security_upgrade -drunhttp -denabletraceserver -ea com.ibm.cubeservices.mdx.server.cubeserver xqe'
            break;
        }
    }
    $StopWatch = [Stopwatch]::StartNew()
    $JQProdLogs = [List[string]]::new()
    For ($i = 0; $i -lt $MaxMsgs; $i++) {
        $JQProdLogs.add($([PSCustomObject]@{
            size = $i
            account = "eric"
            amount = $MaxMsgs
            dip = "127.0.0.1"
            login = "eric"
            objectname = "running sample logs with production jq"
            process = "powershell.exe"
            parentprocessname = "vscode.exe"
            quantity = $j
            subject = $OGMessage 
            url = "https://rally1.rallydev.com/#/331029810028ud/dashboard?detail=%2Fdefect%2F613116013883&fdp=true"
            useragent = $null   
            "timestamp.iso8601" = $('{0:yyyy-MM-ddTHH:mm:ssZ}' -f $($(get-date).ToUniversalTime()))
            whsdp = $true
            fullyqualifiedbeatname = "webhookbeat_JQ_ProdCurrent"
        } | ConvertTo-Json -Compress -Depth 3))
    }

    Invoke-Async -Params $Params -Set $JQProdLogs -SetParam Body -Cmdlet 'Invoke-RestMethod'

    $StopWatch.Stop()
    write-host "$(Get-Date) - OC JQ Test - Msg Qty: $($MaxMsgs)  Msg Size: $MsgSize  Total Time to Submit: $($StopWatch.Elapsed.TotalSeconds)  MPS: $($($MaxMsgs) / $($StopWatch.Elapsed.TotalSeconds))"
    #write-host "$(Get-Date) - OC JQ Test - Pausing for 30 seconds."
    start-sleep -Seconds 90
}