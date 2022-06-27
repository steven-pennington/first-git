<cfcomponent output="no">
    <cffunction name="auditLogEntry" access="public" returntype="void" output="false" hint="Posts to API to log changes">
        <cfargument name="Account_ID" type="numeric" required="yes" />
        <cfargument name="ds" type="string" required="yes" />
        <cfargument name="EmployeeID" type="numeric" required="yes" />
        <cfargument name="residentID" type="numeric" required="no" default="0" />
        <cfargument name="area" type="string" required="yes" default="Task Charting" hint="Part of the program, like Resident File, Charting, etc." />
        <cfargument name="tableName" type="string" required="yes" hint="RESIDENTS, TASK_DETAILS, etc." />
        <cfargument name="rowId" type="numeric" required="yes" hint="The ID of the record in tableName" />
        <cfargument name="oldData" type="query" required="true" />
        <cfargument name="newData" type="query" required="false" default="#QueryNew('')#" hint="Won't have for delete actions" />
        <cfargument name="action" type="string" required="yes" hint="Change, Delete" />
        <cfargument name="Employee_IP" type="string" required="yes" default="#CGI.REMOTE_ADDR#" />
        <cfargument name="event_id" type="string" required="true" default="#CreateUUID()#" />
        
        <cfset var auditLogURL = "https://logging.ecp123.com/auditLog" />
        <cfset var apiKey = "UXJzNHY0QmdyZjRQeHFEb1QzMldwMVhYd1BWcnBaRzM=" />
        <cfset var exclusions = ["TD_AI_ID"] />
        <cfset var inclusions = ["TASK_AI_ID", "TASK_TYPE_ID", "TASK_ID","DATE_ID"] />
        <cfset var resident = "" />
        <cfset var community = "" />
        <cfset var getResId = "" />
        <cfset var getResName = "" />
        <cfset var getTaskType = "" />
        <cfset var rData = "" />
        
        <cfif CGI.SERVER_NAME neq "secure.ecp123.com">
            <cfset auditLogURL = "http://13.92.128.76:3001/auditLog" />
            <cfset apiKey = "NlVHbjNpKioqbmg4UGlaSXZONFk0N0xJbWo1NGIy" />
        </cfif>
        
        <cfif arguments.oldData.recordCount>

            <cftry>
                <cftry>
                    <!--- get user's IP from header that the firewall or load balancer passes us --->
                    <cfif structKeyExists(GetHttpRequestData().headers,'X-Forwarded-For')>
                        <cfset arguments.Employee_IP = GetHttpRequestData().headers["X-Forwarded-For"] />
                    </cfif>
                    <cfcatch></cfcatch>
                </cftry>
                
                <cfset var thisBlock = "" />
                <cfset var dataBlock = ArrayNew(1) />
                <!--- If residentId isn't passed then  we should try to find it in the oldData Query --->
                <cfif arguments.residentID eq 0>
                    <!--- Look for Resident_Id or residentId in the query --->
                    <cfif QueryKeyExists(arguments.oldData, "residentID")>
                        <cfset arguments.residentID = QueryGetRow(arguments.oldData,1).residentID />
                    <cfelseif QueryKeyExists(arguments.oldData, "resident_ID")>
                        <cfset arguments.residentID = QueryGetRow(arguments.oldData,1).resident_ID />
                    </cfif>
                    <cfif arguments.residentId eq 0>
                        <!--- Look it up by task_id --->
                        <cfif QueryKeyExists(arguments.oldData, "task_id")>
                            <cfquery name="getResId" datasource="#arguments.ds#">
                                SELECT RESIDENTID 
                                FROM dbo.TASKS
                                WHERE TASK_ID = <cfqueryparam cfsqltype="cf_sql_integer" value="#QueryGetRow(arguments.oldData,1).TASK_ID#" />
                            </cfquery>
                            <cfif getResId.recordCount>
                                <cfset arguments.residentID = getResId.RESIDENTID />
                            </cfif>
                        <cfelseif QueryKeyExists(arguments.oldData, "task_detail_id")>
                            <cfquery name="getResId" datasource="#arguments.ds#">
                                SELECT T.RESIDENTID 
                                FROM dbo.TASK_DETAILS as TD
                                INNER JOIN dbo.TASKS as T on T.TASK_ID = TD.TASK_ID
                                WHERE TD.TASK_DETAIL_ID = <cfqueryparam cfsqltype="cf_sql_integer" value="#QueryGetRow(arguments.oldData,1).TASK_DETAIL_ID#" />
                            </cfquery>
                            <cfif getResId.recordCount>
                                <cfset arguments.residentID = getResId.RESIDENTID />
                            </cfif>
                        </cfif>
                    </cfif>
                </cfif>
                <cfif arguments.residentID>
                    <!--- Get resident name --->
                    <cfquery name="getResName" datasource="#APPLICATION.obj.user.getDBAlias()#">
                        SELECT FirstName + ' ' + LastName as NAME
                        FROM dbo.RESIDENTS
                        WHERE RESIDENTId = <cfqueryParam cfsqltype="cf_sql_integer" value="#arguments.residentID#" />
                    </cfquery>
                    <cfset resident = getResName.NAME />
                </cfif>
                <!--- Get Community Name --->
                <cfset community = APPLICATION.obj.user.getCompany()>
                <!--- Try to get the otask type from the details --->
                <!---
                    86 = med
                    135 = observation
                    133 = incident report observations
                    134 = investigation report observations
                --->
                <cfif arguments.area eq "Vitals">
                    <cfset arguments.area = "Vitals" />
                <cfelseif queryKeyExists(arguments.oldData, "task_id")>
                    <!--- Get tak type from task record --->
                    <cfquery name="getTaskType" datasource="#arguments.ds#">
                        SELECT top(1) task_type_id from dbo.tasks
                        where task_id = <cfqueryparam cfsqltype="cf_sql_integer" value="#QueryGetRow(arguments.oldData,1).TASK_ID#" />
                    </cfquery>
                    <cfif getTaskType.recordCount>
                        <cfswitch expression="#QueryGetRow(getTaskType,1).TASK_TYPE_ID#">
                            <cfcase value="86">
                                <cfset arguments.area = "Med Charting" />
                            </cfcase>
                            <cfcase value="135">
                                <cfset arguments.area = "Observation" />
                            </cfcase>
                            <cfcase value="133">
                                <cfset arguments.area = "Observation" />
                            </cfcase>
                            <cfcase value="134">
                                <cfset arguments.area = "Observation" />
                            </cfcase>
                            <cfdefaultcase>
                                <cfset arguments.area = "Task Charting" />
                            </cfdefaultcase>
                        </cfswitch>
                    <cfelse>
                        <!--- if there is no task record then that means this was a deleted observation --->
                        <cfset arguments.area = "Observation" />
                    </cfif>
                </cfif>

                <cfif arguments.action eq "Delete">
                    <cfset local.thisBlock = {"oldData": QueryGetRow(arguments.oldData,1)} />
                    <cfset arrayAppend(local.dataBlock,local.thisBlock) />
                <cfelse>
                    <cfloop query="#arguments.oldData#">
                        <cfif arguments.newData.recordCount gte currentRow>
                            <cfset local.thisBlock = {"oldData": QueryGetRow(arguments.oldData,currentRow), "newData": QueryGetRow(arguments.newData,currentRow)} />
                        <cfelse>
                            <cfset local.thisBlock = {"oldData": QueryGetRow(arguments.oldData,currentRow)} />
                        </cfif>
                        <cfset arrayAppend(local.dataBlock,local.thisBlock) />
                    </cfloop>

                    <!--- Capture new data that doesn't match old records --->
                    <cfif arguments.newData.recordCount gt arguments.oldData.recordCount>
                        <cfloop query="#arguments.newData#">
                            <cfif currentRow gt arguments.oldData.recordCount>
                                <cfset local.thisBlock = {"newData": QueryGetRow(arguments.newData,currentRow)} />
                                <cfset arrayAppend(local.dataBlock,local.thisBlock) />
                            </cfif>
                        </cfloop>
                    </cfif>
                </cfif>
                <cfset var sendDataNew = 
                    {
                        "data":  local.dataBlock,
                        "exclusions": local.exclusions,
                        "inclusions": local.inclusions,
                        "user": {
                            "employee_id": '#arguments.EmployeeID#',
                            "employee_ip": '#arguments.Employee_IP#'
                        },
                        "identifiers": {
                            "account_id": '#arguments.Account_ID#',
                            "community_name": '#local.community#',
                            "action": '#arguments.action#',
                            "application_id": 0,
                            "table_name": '#arguments.tableName#',
                            "area": '#arguments.area#',
                            "row_id": '#arguments.rowId#',
                            "resident_id": arguments.residentID,
                            "resident_name": '#local.resident#',
                            "event_id": '#arguments.event_id#'   
                        }
                    } 
                />
                
                <cfset var serializedSendData = serializeJSON(local.sendDataNew) />

                <!--- logging.ecp123.com is set as a record in the C:\Windows\System32\drivers\etc\hosts file on the computer  --->
                <cfhttp method="POST" url="#local.auditLogURL#" result="rData" resolveurl="true">
                    <cfhttpparam type="header" name="Content-Type" value="application/json">
                    <cfhttpparam type="header" name="Accept" value="application/json">
                    <cfhttpparam type="header" name="Authorization" value="Api-Key #local.apiKey#">
                    <cfhttpparam type="body" name="on_order" value="#local.serializedSendData#">
                </cfhttp>

                <!--- We want to log any errors with reaching the audit log server or posting audit log information. --->
                <cfif local.rData.statusCode neq "200 OK">
                    <cfmail to="errors@ecp123.com" from="errors@ecp123.com" subject="Call to Audit Log failed with code #local.rData.statusCode# #cgi.server_name#" type="text" server="smtp.mandrillapp.com" username="ECP" password="#APPLICATION.mandrillPass#" port="587">
                        <cfoutput>
                            #local.serializedSendData#
                        </cfoutput>
                    </cfmail>
                </cfif>

                <!--- Error logging for failures --->
                <cfcatch>
                    <!--- Do we want to catch these errors. Also, I'm not sure how that will work with threads. --->
                    <cfinvoke component="#REQUEST.mapping#.cfc.extendedcarepro.errors" method="logError">
                        <cfif isDefined("cfcatch")>
                            <cfinvokeargument name="theCFCATCH" value="#cfcatch#">
                        </cfif>
                        <cfif isDefined("arguments")>
                            <cfinvokeargument name="theArguments" value="#arguments#">
                        </cfif>
                    </cfinvoke>
                </cfcatch>
            </cftry>
        </cfif>

        <cfreturn />
    </cffunction>

    <cffunction name="auditLogEntryAnswers" access="public" returnType="void" output="false" hint="Posts to API to log answer changes">
        <cfargument name="Account_ID" type="numeric" required="yes" />
        <cfargument name="ds" type="string" required="yes" />
        <cfargument name="EmployeeID" type="numeric" required="yes" />
        <cfargument name="residentID" type="numeric" required="no" default="0" />
        <cfargument name="area" type="string" required="yes" default="Task Charting" hint="Part of the program, like Resident File, Charting, etc." />
        <cfargument name="tableName" type="string" required="yes" hint="RESIDENTS, TASK_DETAILS, etc." />
        <cfargument name="rowId" type="numeric" required="yes" hint="The ID of the record in tableName" />
        <cfargument name="oldData" type="struct" required="true" />
        <cfargument name="newData" type="struct" required="false" default="#StructNew()#" hint="Won't have for delete actions" />
        <cfargument name="action" type="string" required="yes" hint="Change, Delete" />
        <cfargument name="Employee_IP" type="string" required="yes" default="#CGI.REMOTE_ADDR#" />
        <cfargument name="event_id" type="string" required="true" default="#CreateUUID()#" />
        
        <cfset var auditLogURL = "https://logging.ecp123.com/auditLog" />
        <cfset var apiKey = "UXJzNHY0QmdyZjRQeHFEb1QzMldwMVhYd1BWcnBaRzM=" />
        <cfset var exclusions = ["TD_AI_ID"] />
        <cfset var inclusions = ["TASK_AI_ID", "TASK_TYPE_ID", "TASK_ID"] />
        <cfset var resident = "" />
        <cfset var community = "" />
        <cfset var getResId = "" />
        <cfset var getResName = "" />
        <cfset var getTaskType = "" />
        <cfset var rData = "" />

        <cfif CGI.SERVER_NAME neq "secure.ecp123.com">
            <cfset auditLogURL = "http://13.92.128.76:3001/auditLog" />
            <cfset apiKey = "NlVHbjNpKioqbmg4UGlaSXZONFk0N0xJbWo1NGIy" />
        </cfif>
        <cfif structCount(arguments.oldData)>

            <cftry>
                <cftry>
                    <!--- get user's IP from header that the firewall or load balancer passes us --->
                    <cfif structKeyExists(GetHttpRequestData().headers,'X-Forwarded-For')>
                        <cfset arguments.Employee_IP = GetHttpRequestData().headers["X-Forwarded-For"] />
                    </cfif>
                    <cfcatch></cfcatch>
                </cftry>
                
                <cfset var thisBlock = "" />
                <cfset var dataBlock = [] />
                <!--- If residentId isn't passed then  we should try to find it in the oldData Query --->
                <!--- Look it up by task_detail_id --->
                <cfif arguments.rowId neq 0>
                    <cfquery name="getResId" datasource="#arguments.ds#">
                        SELECT T.RESIDENTID, T.TASK_ID
                        FROM dbo.TASK_DETAILS as TD
                        INNER JOIN dbo.TASKS as T on T.TASK_ID = TD.TASK_ID
                        WHERE TD.TASK_DETAIL_ID = <cfqueryparam cfsqltype="cf_sql_integer" value="#arguments.rowId#" />
                    </cfquery>
                    <cfif getResId.recordCount>
                        <cfset arguments.residentID = getResId.RESIDENTID />
                    </cfif>
                </cfif>
                <cfif arguments.residentID gt 0>
                    <!--- Get resident name --->
                    <cfquery name="getResName" datasource="#APPLICATION.obj.user.getDBAlias()#">
                        SELECT FirstName + ' ' + LastName as NAME
                        FROM dbo.RESIDENTS
                        WHERE RESIDENTId = <cfqueryParam cfsqltype="cf_sql_integer" value="#arguments.residentID#" />
                    </cfquery>
                    <cfset resident = getResName.NAME />
                </cfif>
                <!--- Get Community Name --->
                <cfset community = APPLICATION.obj.user.getCompany()>

                <!--- Try to get the otask type from the details --->
                <!---
                    86 = med
                    135 = observation
                    133 = incident report observations
                    134 = investigation report observations
                --->
                <cfif arguments.area eq "Vitals">
                    <cfset arguments.area = "Vitals" />
                <cfelseif getResId.recordCount and getResId.TASK_ID neq 0>
                    <!--- Get tak type from task record --->
                    <cfquery name="getTaskType" datasource="#arguments.ds#">
                        SELECT top(1) task_type_id from dbo.tasks
                        where task_id = <cfqueryparam cfsqltype="cf_sql_integer" value="#getResId.TASK_ID#" />
                    </cfquery>
                    <cfif getTaskType.recordCount gt 0>
                        <cfswitch expression="#QueryGetRow(getTaskType,1).TASK_TYPE_ID#">
                            <cfcase value="86">
                                <cfset arguments.area = "Med Charting" />
                            </cfcase>
                            <cfcase value="135">
                                <cfset arguments.area = "Observation" />
                            </cfcase>
                            <cfcase value="133">
                                <cfset arguments.area = "Observation" />
                            </cfcase>
                            <cfcase value="134">
                                <cfset arguments.area = "Observation" />
                            </cfcase>
                            <cfdefaultcase>
                                <cfset arguments.area = "Task Charting" />
                            </cfdefaultcase>
                        </cfswitch>
                    <cfelse>
                        <!--- if there is no task record then that means this was a deleted observation --->
                        <cfset arguments.area = "Observation" />
                    </cfif>
                </cfif>

                <cfset var sendDataNew = 
                    {
                        "data":  [{
                            "oldData": arguments.oldData,
                            "newData": arguments.newData
                        }],
                        "exclusions": local.exclusions,
                        "inclusions": local.inclusions,
                        "user": {
                            "employee_id": '#arguments.EmployeeID#',
                            "employee_ip": '#arguments.Employee_IP#'
                        },
                        "identifiers": {
                            "account_id": '#arguments.Account_ID#',
                            "community_name": '#local.community#',
                            "action": '#arguments.action#',
                            "application_id": 0,
                            "table_name": '#arguments.tableName#',
                            "area": '#arguments.area#',
                            "row_id": '#arguments.rowId#',
                            "resident_id": arguments.residentID,
                            "resident_name": '#local.resident#',
                            "event_id": '#arguments.event_id#'   
                        }
                    } 
                />
                
                <cfset var serializedSendData = serializeJSON(local.sendDataNew,'struct') />
                
                <!--- logging.ecp123.com is set as a record in the C:\Windows\System32\drivers\etc\hosts file on the computer  --->
                <cfhttp method="POST" url="#local.auditLogURL#" result="rData" resolveurl="true">
                    <cfhttpparam type="header" name="Content-Type" value="application/json">
                    <cfhttpparam type="header" name="Accept" value="application/json">
                    <cfhttpparam type="header" name="Authorization" value="Api-Key #local.apiKey#">
                    <cfhttpparam type="body" name="on_order" value="#local.serializedSendData#">
                </cfhttp>

                <!--- We want to log any errors with reaching the audit log server or posting audit log information. --->
                <cfif local.rData.statusCode neq "200 OK">
                    <cfmail to="errors@ecp123.com" from="errors@ecp123.com" subject="Call to Audit Log failed with code #local.rData.statusCode# #cgi.server_name#" type="text" server="smtp.mandrillapp.com" username="ECP" password="#APPLICATION.mandrillPass#" port="587">
                        <cfoutput>
                            #local.serializedSendData#
                        </cfoutput>
                    </cfmail>
                </cfif>

                <!--- Error logging for failures --->
                <cfcatch>
                   
                    <!--- Do we want to catch these errors. Also, I'm not sure how that will work with threads. --->
                    <cfinvoke component="#REQUEST.mapping#.cfc.extendedcarepro.errors" method="logError">
                        <cfif isDefined("cfcatch")>
                            <cfinvokeargument name="theCFCATCH" value="#cfcatch#">
                        </cfif>
                        <cfif isDefined("arguments")>
                            <cfinvokeargument name="theArguments" value="#arguments#">
                        </cfif>
                    </cfinvoke>
                </cfcatch>
            </cftry>
        </cfif>
        <cfreturn />
    </cffunction>

    <!--- unreferenced --->
    <!--- <cfscript>
        function structGetKey(theStruct, theKey, defaultVal){
            if (structKeyExists(arguments.theStruct, arguments.theKey)){
                return arguments.theStruct[arguments.theKey];
            }else{
                return arguments.defaultVal;
            }
        }
    </cfscript> --->

    <cffunction name="qryAuditLog" access="public" returntype="any" output="false" hint="Call API to retrieve data for Audit Log report">
        <cfargument name="account_id" type="string" />
        <cfargument name="action" type="string" />
        <cfargument name="application_id" type="numeric" default="0" />
        <cfargument name="start_date" type="string" />
        <cfargument name="end_date" type="string" />
        <cfargument name="identifiers" type="any" />
        <cfargument name="event_id" type="string" required="no" />

        <cfset var rData = "" />
        <cfset var results = [] />
        <cfset var getTimeZone = "" />
        <cfset var auditLogQuery = QueryNew("ID, ACCOUNT_ID, EVENT_ID,TASK_TYPE_ID,DATE_TIME,EMPLOYEE_ID,RESIDENT_ID,RESIDENT_NAME,COMMUNITY_NAME, ACTION, AREA, IP_ADDRESS, JSON, OGDATE") />
        <cfset var i = "" />

        <cfset var auditLogURL = "https://logging.ecp123.com/auditLog" />
        <cfset var apiKey = "UXJzNHY0QmdyZjRQeHFEb1QzMldwMVhYd1BWcnBaRzM=" />
        <cfif CGI.SERVER_NAME neq "secure.ecp123.com">
            <cfset auditLogURL = "http://13.92.128.76:3001/auditLog" />
            <cfset apiKey = "NlVHbjNpKioqbmg4UGlaSXZONFk0N0xJbWo1NGIy" />
        </cfif>

        <!--- 
            build url params to send
            action - (if it's delete, will not return newData)
            start_date and end_date
            and then identifiers we want to look for
        --->

        <cfif structKeyExists(arguments, "event_id")>
            <cfset auditLogURL = auditLogURL & "?event_id=#arguments.event_id#" />
        </cfif>
        <cfquery name="getTimeZone" datasource="ECP">
            SELECT IANA_TIMEZONE 
            FROM ECP.dbo.ACCOUNTS
            WHERE dbalias = <cfqueryparam cfsqltype="cf_sql_varchar" value="#APPLICATION.obj.USER.getdbAlias()#">
        </cfquery>
        
        <cfset var startDate1 = "#Dateformat(arguments.start_date, 'yyyy-mm-dd')# 00:00:00" />
        <cfset var endDate1 = "#Dateformat(arguments.end_date, 'yyyy-mm-dd')# 23:59:00" />

        <cfset var startDate2 = toUTC(local.startDate1, local.getTimeZone.IANA_TIMEZONE) />
        <cfset var endDate2 = toUTC(local.endDate1, local.getTimeZone.IANA_TIMEZONE) />

        <cfset var startDate = DateTimeFormat(local.startDate2, 'yyyy-mm-dd HH:nn:ss')>
        <cfset var endDate = DateTimeFormat(local.endDate2, 'yyyy-mm-dd HH:nn:ss')>
        <!--- Get the Data --->
        <cfhttp method="GET" url="#local.auditLogURL#" result="rData" resolveurl="true">
            <cfhttpparam type="header" name="Content-Type" value="application/json">
            <cfhttpparam type="header" name="Accept" value="application/json">
            <cfhttpparam type="header" name="Authorization" value="Api-Key #local.apiKey#">
            <cfhttpparam type="url" name="account_id" value="#arguments.account_id#">
            <!--- <cfif structKeyExists(arguments, "identifiers")>
                <cfloop collection="#arguments.identifiers#" item="key" >
                    <cfhttpparam type="url" name="#trim(Key)#" value="#trim(identifiers[key])#">
                </cfloop>
            </cfif> --->
            <cfif structKeyExists(arguments, "action")>
                <cfhttpparam type="url" name="action" value="#arguments.action#">
            </cfif>
            <cfif structKeyExists(arguments, "start_date")>
                <cfhttpparam type="url" name="start_date" value="#local.startDate#">
            </cfif>
            <cfif structKeyExists(arguments, "end_date")>
                <cfhttpparam type="url" name="end_date" value="#local.endDate#">
            </cfif>
        </cfhttp>

        <cfif local.rData.statusCode eq "200 OK" and isJSON(local.rData.FileContent)>
            <cfset local.results = deserializeJSON(local.rData.FileContent) />

            <!--- Let's build a query out of our data that we display for the list. This will allow us to group by whatever --->
            
            <cfloop from="1" to="#ArrayLen(local.results)#" index="i">
                <cfset QueryAddRow(auditLogQuery) />
                <cfset QuerySetCell(auditLogQuery,"ACCOUNT_ID", local.results[i]["identifiers"]["account_id"]) />
                <cfset QuerySetCell(auditLogQuery,"EVENT_ID", local.results[i]["identifiers"]["event_id"]) />
                <cfset QuerySetCell(auditLogQuery,"DATE_TIME", local.results[i]["createdAt"]) />
                <cfset QuerySetCell(auditLogQuery,"EMPLOYEE_ID", local.results[i]["user"]["employee_id"]) />
                <cfset QuerySetCell(auditLogQuery,"RESIDENT_ID", local.results[i]["identifiers"]["resident_id"]) />
                <cfset QuerySetCell(auditLogQuery,"ACTION", local.results[i]["identifiers"]["action"]) />
                <cfset QuerySetCell(auditLogQuery,"AREA", local.results[i]["identifiers"]["area"]) />
                <cfset QuerySetCell(auditLogQuery,"IP_ADDRESS", local.results[i]["user"]["employee_ip"]) />
                <cfset QuerySetCell(auditLogQuery,"JSON", serializeJSON(local.results[i])) />
                <cfset QuerySetCell(auditLogQuery,"OGDATE", local.results[i]["createdAt"]) />
            </cfloop>
        </cfif>

        <cfset local.success = (local.rData.statusCode eq "200 OK") ? true : false />

        <cfset local.returnStruct = structNew() />
        <cfset local.returnStruct.auditLogQuery = local.auditLogQuery />
        <cfset local.returnStruct.success = local.success />

        <!--- We want to log any errors with retrieving audit log information.  If there is an error when opening the audit log, we will display an error message. --->
        <cfif !local.success>
            <cfset local.theCFCATCH = structNew() />
            <cfset local.theCFCATCH["message"] = "Audit log returned #local.rData.statusCode#" />
            <cfinvoke component="#REQUEST.mapping#.cfc.extendedcarepro.errors" method="logError" returnVariable="local.errorId">
                <cfinvokeargument name="theCFCATCH" value="#local.theCFCATCH#">
            </cfinvoke>
            <cfset local.returnStruct.errorId = local.errorId />
        </cfif>

        <cfreturn local.returnStruct />
    </cffunction>

    <cfscript>
        //unreferenced
        /*
        function GetEpochTime() {
            var datetime = 0;
            if (ArrayLen(Arguments) is 0) {
                datetime = Now();
        
            }
            else {
                if (isValid("Date",Arguments[1])) {
                    datetime = Arguments[1];
                } else {
                    return NULL;
                }
            }
            return DateDiff("s", "January 1 1970 00:00", datetime);
        }
        */

        function toUTC( required time, tz = "America/New_York" ){
            var timezone = createObject("java", "java.util.TimeZone").getTimezone( tz );
            var ms = timezone.getOffset( getTickCount() ); //get this timezone's current offset from UTC
            var seconds = ms / 1000;
            return dateAdd( 's', -1 * seconds, time );
        }

        //unreferenced
        /*
        function UTCtoTZ( required time, required string tz ){
            var timezone = createObject("java", "java.util.TimeZone").getTimezone( tz );
            var ms = timezone.getOffset( getTickCount() ); //get this timezone's current offset from UTC
            var seconds = ms / 1000;
            return dateAdd( 's', seconds, time );
        }
        */
    </cfscript>

    <cffunction name="qryAuditLogDetails" access="public" returntype="any" output="false" hint="Calls API for changes that were logged ">
        <cfargument name="account_id" type="numeric" required="yes" />
        <cfargument name="event_id" type="string" required="yes" />

        <cfset var rData = "" />
        <cfset var results = ArrayNew(1) /> 

        <cfset var auditLogURL = "https://logging.ecp123.com/auditLog" />
        <cfset var apiKey = "UXJzNHY0QmdyZjRQeHFEb1QzMldwMVhYd1BWcnBaRzM=" />
        <cfif CGI.SERVER_NAME neq "secure.ecp123.com">
            <cfset auditLogURL = "http://13.92.128.76:3001/auditLog" />
            <cfset apiKey = "NlVHbjNpKioqbmg4UGlaSXZONFk0N0xJbWo1NGIy" />
        </cfif>

        <!--- 
            build url params to send
            action - (if it's delete, will not return newData)
            start_date and end_date  
            and then identifiers we want to look for
        --->

        <cfif structKeyExists(arguments, "event_id")>
            <cfset local.auditLogURL = local.auditLogURL & "?event_id=#arguments.event_id#" />
        </cfif>

        <!--- Get the Data --->
        <cfhttp method="GET" url="#local.auditLogURL#" result="rData" resolveurl="true">
            <cfhttpparam type="header" name="Content-Type" value="application/json">
            <cfhttpparam type="header" name="Accept" value="application/json">
            <cfhttpparam type="header" name="Authorization" value="Api-Key #local.apiKey#">
            <cfhttpparam type="url" name="account_id" value="#arguments.account_id#">
        </cfhttp>

        <cfif local.rData.statusCode eq "200 OK" and isJSON(local.rData.FileContent)>
            <cfset local.results = deserializeJSON(local.rData.FileContent) />
        </cfif>
       
        <cfreturn local.results />

    </cffunction>

    <cffunction name="friendlyAuditLabel" access="public" returntype="string" output="false" hint="Audit details window calls this function to convert the database field name to the label displayed in ECP">
        <cfargument name="field" type="string" required="true" />
        <cfargument name="table" type="string" required="true" default="TASK_DETAILS" />

        <cfset var friendlyLabel = "" />
        <cfset var getPrefs = APPLICATION.obj.user.getPrefs() />
        <cfswitch expression="#arguments.table#">
            <cfcase value="TASK_DETAILS">
                <cfswitch expression="#arguments.field#">
                    <cfcase value='TASK_DETAIL_ID'>
                        <cfset local.friendlyLabel = "" />
                    </cfcase>
                    <cfcase value='TASK_ID'>
                        <cfset local.friendlyLabel = "" />
                    </cfcase>
                    <cfcase value='DATE_ID'>
                        <cfset local.friendlyLabel = "" />
                    </cfcase>
                    <cfcase value='DISPLAY_LABEL'>
                        <cfset local.friendlyLabel = "" />
                    </cfcase>
                    <cfcase value='ASSIGN_GROUPID'>
                        <cfset local.friendlyLabel = "Responsible Task Group" />
                    </cfcase>
                    <cfcase value='ASSIGN_EMPLOYEEID'>
                        <cfset local.friendlyLabel = "Assigned Employee" />
                    </cfcase>
                    <cfcase value='INITIALS'>
                        <cfset local.friendlyLabel = "Charting Initials" />
                    </cfcase>
                    <cfcase value='DATE_TIME_COMPLETED'>
                        <cfset local.friendlyLabel = "Charted On" />
                    </cfcase>
                    <cfcase value='DATE_TIME_POSTED'>
                        <cfset local.friendlyLabel = "" />
                    </cfcase>
                    <cfcase value='APPLICATION_ID'>
                        <cfset local.friendlyLabel = "" />
                    </cfcase>
                    <cfcase value='NO_GO_ID'>
                        <cfset local.friendlyLabel = "Refusal Reason" />
                    </cfcase>
                    <cfcase value='NO_GO_NOTES'>
                        <cfset local.friendlyLabel = "Refusal Notes" />
                    </cfcase>
                    <cfcase value='PULSE'>
                        <cfset local.friendlyLabel = "Pulse" />
                    </cfcase>
                    <cfcase value='SYSTOLIC'>
                        <cfset local.friendlyLabel = "Blood Pressure Systolic" />
                    </cfcase>
                    <cfcase value='DIASTOLIC'>
                        <cfset local.friendlyLabel = "Blood Pressure Diastolic" />
                    </cfcase>
                    <cfcase value='WEIGHT'>
                        <cfset local.friendlyLabel = "Weight" />
                    </cfcase>
                    <cfcase value='TEMPERATURE'>
                        <cfset local.friendlyLabel = "Temperature" />
                    </cfcase>
                    <cfcase value='RESPIRATIONS'>
                        <cfset local.friendlyLabel = "Respirations" />
                    </cfcase>
                    <cfcase value='BLOODSUGAR'>
                        <cfset local.friendlyLabel = "Blood Sugar" />
                    </cfcase>
                    <cfcase value='PULSEOX'>
                        <cfset local.friendlyLabel = "Pulseox" />
                    </cfcase>
                    <cfcase value='BLOODPRESSURE'>
                        <cfset local.friendlyLabel = "Blood Pressure" />
                    </cfcase>
                    <cfcase value='EMPLOYEEID'>
                        <cfset local.friendlyLabel = "Employee" />
                    </cfcase>
                    <cfcase value='COST'>
                        <cfset local.friendlyLabel = "Cost" />
                    </cfcase>
                    <cfcase value='UNITS'>
                        <cfset local.friendlyLabel = "Minutes" />
                    </cfcase>
                    <cfcase value='NOTES'>
                        <cfset local.friendlyLabel = "Notes" />
                    </cfcase>
                    <cfcase value='LIST_ITEM_ID'>
                        <cfset local.friendlyLabel = "" />
                    </cfcase>
                    <cfcase value='UPDATED_EMPLOYEE'>
                        <cfset local.friendlyLabel = "Update Employee" />
                    </cfcase>
                    <cfcase value='UPDATED_DATE'>
                        <cfset local.friendlyLabel = "Updated Time" />
                    </cfcase>
                    <cfcase value='ISP_STATUS'>
                        <cfset local.friendlyLabel = "<cfoutput>#local.getPrefs.ISP_CURRENT_STATUS#</cfoutput>" />
                    </cfcase> 
                    <cfcase value='ISP_GOALS'>
                        <cfset local.friendlyLabel = "<cfoutput>#local.getPrefs.ISP_GOALS#</cfoutput>" />
                    </cfcase>
                    <cfcase value='ISP_PROVIDER'>
                        <cfset local.friendlyLabel = "<cfoutput>#local.getPrefs.ISP_PROVIDER#</cfoutput>" />
                    </cfcase>
                    <cfcase value='ISP_CHANGES'>
                        <cfset local.friendlyLabel = "<cfoutput>#local.getPrefs.ISP_CHANGES#</cfoutput>" />
                    </cfcase>
                    <cfcase value='PAIN_LEVEL'>
                        <cfset local.friendlyLabel = "Pain Level" />
                    </cfcase>
                    <cfcase value='RED_FLAG'>
                        <cfset local.friendlyLabel = "Flag as Important" />
                    </cfcase>
                    <cfcase value='PREP_DATE_TIME'>
                        <cfset local.friendlyLabel = "Prep Date/Time" />
                    </cfcase> 
                    <cfcase value='PREP_EMPLOYEE_ID'>
                        <cfset local.friendlyLabel = "Prepped By" />
                    </cfcase>
                    <cfcase value='PREP_INITIALS'>
                        <cfset local.friendlyLabel = "Prep Initials" />
                    </cfcase>
                    <cfcase value='QTY_PER_ISSUE'>
                        <cfset local.friendlyLabel = "Quantity Passed" />
                    </cfcase>
                    <cfcase value='EMPLOYEE_CHARTING_COST'>
                        <cfset local.friendlyLabel = "" />
                    </cfcase>
                    <cfcase value='EMPLOYEE_CHARTING_POINTS'>
                        <cfset local.friendlyLabel = "" />
                    </cfcase>
                    <cfcase value='VITALS_DATE_TIME'>
                        <cfset local.friendlyLabel = "" />
                    </cfcase>
                    <cfcase value='VITALS_EMPLOYEE_ID'>
                        <cfset local.friendlyLabel = "" />
                    </cfcase>
                    <cfcase value='QUESTIONS_DATE_TIME'>
                        <cfset local.friendlyLabel = "" />
                    </cfcase>
                    <cfcase value='QUESTIONS_EMPLOYEE_ID'>
                        <cfset local.friendlyLabel = "" />
                    </cfcase>
                    <cfcase value='ERROR_TYPE'>
                        <cfset local.friendlyLabel = "Error Type" />
                    </cfcase>
                    <cfcase value='ERROR_REASON'>
                        <cfset local.friendlyLabel = "Error Reason" />
                    </cfcase>
                    <cfcase value='ADVERSE_EFFECT'>
                        <cfset local.friendlyLabel = "Was there a serious adverse effect associated with this error?" />
                    </cfcase>
                </cfswitch>
            </cfcase>
            <cfcase value="TASK_DETAILS_AI">
                <cfswitch expression="#arguments.field#">
                    <cfcase value='VERSION_TASK_AI_ID'>
                        <cfset local.friendlyLabel = "" />
                    </cfcase>
                    <cfcase value='TASK_AI_ID'>
                        <cfset local.friendlyLabel = "" />
                    </cfcase>
                    <cfcase value='TASK_DETAIL_ID'>
                        <cfset local.friendlyLabel = "" />
                    </cfcase>
                    <cfcase value='TD_AI_ID'>
                        <cfset local.friendlyLabel = "" />
                    </cfcase>
                    <cfcase value='VALUE_TEXT'>
                        <cfset local.friendlyLabel = "Text Answer" />
                    </cfcase>
                    <cfcase value='VALUE_NUM'>
                        <cfset local.friendlyLabel = "Answer" />
                    </cfcase>
                </cfswitch>
            </cfcase>
        </cfswitch>

        <cfreturn LOCAL.friendlyLabel />
    </cffunction>

    <cffunction name="buildLogDates" output="false" access="public" returnType="struct" hint="Audit log report calls this function to get dates associated with options">
		<cfargument name="auditRange" type="numeric" required="true" />

		<cfset var dateStruct = structNew() />
		<cfset local.dateStruct.auditStart = '' />
		<cfset local.dateStruct.auditEnd = '' />
		<cfset local.dateStruct.thisQuarterStart = '' />
		<cfset local.dateStruct.thisQuarterEnd = '' />
		<cfset local.dateStruct.lastQuarterStart = '' />
		<cfset local.dateStruct.lastQuarterEnd = '' />

		<cfset var currentDate = application.obj.user.getUserTime() />
		<cfset local.dateStruct.thisMonthStart = dateFormat(local.currentDate,'mm/01/yyyy') />
		<cfset var endDay = daysInMonth(local.dateStruct.thisMonthStart) />
		<cfset local.dateStruct.thisMonthEnd = dateFormat(local.dateStruct.thisMonthStart,'mm/#local.endDay#/yyyy') />

		<cfset local.dateStruct.lastMonthStart = dateFormat(dateAdd('m',-1,local.currentDate),'mm/01/yyyy') />
		<cfset local.endDay = daysInMonth(local.dateStruct.lastMonthStart) />
		<cfset local.dateStruct.lastMonthEnd = dateFormat(local.dateStruct.lastMonthStart,'mm/#local.endDay#/yyyy') />

		<cfswitch expression="#quarter(local.currentDate)#">
			<cfcase value="1">
				<cfset local.dateStruct.thisQuarterStart = '01/01/#year(local.currentDate)#' />
				<cfset local.dateStruct.thisQuarterEnd = '03/31/#year(local.currentDate)#' />
			</cfcase>
			<cfcase value="2">
				<cfset local.dateStruct.thisQuarterStart = '04/01/#year(local.currentDate)#' />
				<cfset local.dateStruct.thisQuarterEnd = '06/30/#year(local.currentDate)#' />
			</cfcase>
			<cfcase value="3">
				<cfset local.dateStruct.thisQuarterStart = '07/01/#year(local.currentDate)#' />
				<cfset local.dateStruct.thisQuarterEnd = '09/30/#year(local.currentDate)#' />
			</cfcase>
			<cfcase value="4">
				<cfset local.dateStruct.thisQuarterStart = '10/01/#year(local.currentDate)#' />
				<cfset local.dateStruct.thisQuarterEnd = '12/31/#year(local.currentDate)#' />
			</cfcase>
		</cfswitch>

		<cfset var lastQuarterDate = dateAdd('q',-1,local.currentDate) />
		<cfswitch expression="#quarter(lastQuarterDate)#">
			<cfcase value="1">
				<cfset local.dateStruct.lastQuarterStart = '01/01/#year(local.lastQuarterDate)#' />
				<cfset local.dateStruct.lastQuarterEnd = '03/31/#year(local.lastQuarterDate)#' />
			</cfcase>
			<cfcase value="2">
				<cfset local.dateStruct.lastQuarterStart = '04/01/#year(local.lastQuarterDate)#' />
				<cfset local.dateStruct.lastQuarterEnd = '06/30/#year(local.lastQuarterDate)#' />
			</cfcase>
			<cfcase value="3">
				<cfset local.dateStruct.lastQuarterStart = '07/01/#year(local.lastQuarterDate)#' />
				<cfset local.dateStruct.lastQuarterEnd = '09/30/#year(local.lastQuarterDate)#' />
			</cfcase>
			<cfcase value="4">
				<cfset local.dateStruct.lastQuarterStart = '10/01/#year(local.lastQuarterDate)#' />
				<cfset local.dateStruct.lastQuarterEnd = '12/31/#year(local.lastQuarterDate)#' />
			</cfcase>
		</cfswitch>

		<cfset local.dateStruct.ytdStart = dateFormat(local.currentDate,'01/01/yyyy') />
		<cfset local.dateStruct.ytdEnd = dateFormat(local.currentDate,'mm/dd/yyyy') />

		<cfset var lastYear = Year(local.currentDate) -1 />
		<cfset local.dateStruct.lastYearStart = '01/01/#local.lastYear#' />
		<cfset local.dateStruct.lastYearEnd = '12/31/#local.lastYear#' />

        <cfset var today = dateFormat(local.currentDate,'mm/dd/yyyy') />
        <cfset local.dateStruct.todayStart = local.today />
        <cfset local.dateStruct.todayEnd = local.today />

        <cfset local.dateStruct.thisWeekStart = dateFormat(local.today - DayOfWeek(local.today ) + 1, 'mm/dd/yyyy') />
        <cfset local.dateStruct.thisWeekEnd = dateFormat(local.today + (7 - DayOfWeek( local.today )), 'mm/dd/yyyy') />

        <cfset var dtLastWeek = (Fix( Now() ) - 7) />
        <cfset local.dateStruct.lastWeekStart = dateFormat(local.dtLastWeek - DayOfWeek( local.dtLastWeek ) + 1, 'mm/dd/yyyy') />
        <cfset local.dateStruct.lastWeekEnd = dateFormat(local.dateStruct.lastWeekStart + 6, 'mm/dd/yyyy') />

		<cfswitch expression="#arguments.auditRange#">
			<cfcase value="1">
				<cfset local.dateStruct.auditStart = local.dateStruct.thisMonthStart />
				<cfset local.dateStruct.auditEnd = local.dateStruct.thisMonthEnd />
			</cfcase>
			<cfcase value="2">
				<cfset local.dateStruct.auditStart = local.dateStruct.lastMonthStart />
				<cfset local.dateStruct.auditEnd = local.dateStruct.lastMonthEnd />
			</cfcase>
			<cfcase value="3">
				<cfset local.dateStruct.auditStart = local.dateStruct.thisQuarterStart />
				<cfset local.dateStruct.auditEnd = local.dateStruct.thisQuarterEnd />
			</cfcase>
			<cfcase value="4">
				<cfset local.dateStruct.auditStart = local.dateStruct.lastQuarterStart />
				<cfset local.dateStruct.auditEnd = local.dateStruct.lastQuarterEnd />
			</cfcase>
			<cfcase value="5">
				<cfset local.dateStruct.auditStart = local.dateStruct.ytdStart />
				<cfset local.dateStruct.auditEnd = local.dateStruct.ytdEnd />
			</cfcase>
			<cfcase value="6">
				<cfset local.dateStruct.auditStart = local.dateStruct.lastYearStart />
				<cfset local.dateStruct.auditEnd = local.dateStruct.lastYearEnd />
			</cfcase>
			<cfcase value="7">
				<cfset local.dateStruct.auditStart = '' />
				<cfset local.dateStruct.auditEnd = '' />
			</cfcase>
            <cfcase value="8">
				<cfset local.dateStruct.auditStart = local.dateStruct.todayStart />
				<cfset local.dateStruct.auditEnd = local.dateStruct.todayEnd />
			</cfcase>
            <cfcase value="9">
				<cfset local.dateStruct.auditStart = local.dateStruct.thisWeekStart />
				<cfset local.dateStruct.auditEnd = local.dateStruct.ThisWeekEnd />
			</cfcase>
            <cfcase value="10">
				<cfset local.dateStruct.auditStart = local.dateStruct.lastWeekStart />
				<cfset local.dateStruct.auditEnd = local.dateStruct.lastWeekEnd />
			</cfcase>
		</cfswitch>

		<cfreturn local.dateStruct />
	</cffunction>

    <cfscript>
        public struct function processQuestionsForLog(required query oldData, required query newData) {
            var returnData = {
                oldData: {},
                newData: {}
            };
            var key = 0;
            cfloop(query="oldData") {
                if (!structKeyExists(returnData.oldData, '#task_ai_id#')) returnData.oldData['#task_ai_id#'] = ArrayNew(1);
                if (Len(VALUE_NUM)) {
                    ArrayAppend(returnData.oldData['#task_ai_id#'], VALUE_NUM);
                } else if (Len(VALUE_TEXT)) {
                    ArrayAppend(returnData.oldData['#task_ai_id#'], VALUE_TEXT);
                }
            }
            cfloop(query="newData") {
                if (!structKeyExists(returnData.newData, '#task_ai_id#')) returnData.newData['#task_ai_id#'] = ArrayNew(1);
                if (Len(VALUE_NUM)) {
                    ArrayAppend(returnData.newData['#task_ai_id#'], VALUE_NUM);
                } else if (Len(VALUE_TEXT)) {
                    ArrayAppend(returnData.newData['#task_ai_id#'], VALUE_TEXT);
                }
            }
            try {
                for( key in returnData.oldData) {
                
                    returnData.oldData[key] = ArrayToList(returnData.oldData[key],'|');
                }
    
                for ( key in returnData.newData) {
                    returnData.newData[key] = ArrayToList(returnData.newData[key], '|');
                }
            } catch (any e) {
                var error = e;
            }

            return returnData;
        }
    </cfscript>
</cfcomponent>