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
        
        <cfset var auditLogURL = "https://LOG_URL/auditLog" />
        <cfset var apiKey = "" />
        <cfset var exclusions = ["TD_AI_ID"] />
        <cfset var inclusions = ["TASK_AI_ID", "TASK_TYPE_ID", "TASK_ID","DATE_ID"] />
        <cfset var resident = "" />
        <cfset var community = "" />
        <cfset var getResId = "" />
        <cfset var getResName = "" />
        <cfset var getTaskType = "" />
        <cfset var rData = "" />
        
        <cfif CGI.SERVER_NAME neq "PROD_SERVER">
            <cfset auditLogURL = "http://LOG_URL/auditLog" />
            <cfset apiKey = "" />
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
                    <cfset thisBlock = {"oldData": QueryGetRow(arguments.oldData,1)} />
                    <cfset arrayAppend(dataBlock,thisBlock) />
                <cfelse>
                    <cfloop query="#arguments.oldData#">
                        <cfif arguments.newData.recordCount gte currentRow>
                            <cfset thisBlock = {"oldData": QueryGetRow(arguments.oldData,currentRow), "newData": QueryGetRow(arguments.newData,currentRow)} />
                        <cfelse>
                            <cfset thisBlock = {"oldData": QueryGetRow(arguments.oldData,currentRow)} />
                        </cfif>
                        <cfset arrayAppend(dataBlock,thisBlock) />
                    </cfloop>

                    <!--- Capture new data that doesn't match old records --->
                    <cfif arguments.newData.recordCount gt arguments.oldData.recordCount>
                        <cfloop query="#arguments.newData#">
                            <cfif currentRow gt arguments.oldData.recordCount>
                                <cfset thisBlock = {"newData": QueryGetRow(arguments.newData,currentRow)} />
                                <cfset arrayAppend(dataBlock,thisBlock) />
                            </cfif>
                        </cfloop>
                    </cfif>
                </cfif>
                <cfset var sendDataNew = 
                    {
                        "data":  dataBlock,
                        "exclusions": exclusions,
                        "inclusions": inclusions,
                        "user": {
                            "employee_id": '#arguments.EmployeeID#',
                            "employee_ip": '#arguments.Employee_IP#'
                        },
                        "identifiers": {
                            "account_id": '#arguments.Account_ID#',
                            "community_name": '#community#',
                            "action": '#arguments.action#',
                            "application_id": 0,
                            "table_name": '#arguments.tableName#',
                            "area": '#arguments.area#',
                            "row_id": '#arguments.rowId#',
                            "resident_id": arguments.residentID,
                            "resident_name": '#resident#',
                            "event_id": '#arguments.event_id#'   
                        }
                    } 
                />
                
                <cfset var serializedSendData = serializeJSON(sendDataNew) />

                <cfhttp method="POST" url="#auditLogURL#" result="rData" resolveurl="true">
                    <cfhttpparam type="header" name="Content-Type" value="application/json">
                    <cfhttpparam type="header" name="Accept" value="application/json">
                    <cfhttpparam type="header" name="Authorization" value="Api-Key #apiKey#">
                    <cfhttpparam type="body" name="on_order" value="#serializedSendData#">
                </cfhttp>

                <!--- We want to log any errors with reaching the audit log server or posting audit log information. --->
                <cfif rData.statusCode neq "200 OK">
                    <cfmail to="errors" from="errors" subject="Call to Audit Log failed with code #rData.statusCode# #cgi.server_name#" type="text">
                        <cfoutput>
                            #serializedSendData#
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
        
        <cfset var auditLogURL = "https://LOG_URL/auditLog" />
        <cfset var apiKey = "=" />
        <cfset var exclusions = ["TD_AI_ID"] />
        <cfset var inclusions = ["TASK_AI_ID", "TASK_TYPE_ID", "TASK_ID"] />
        <cfset var resident = "" />
        <cfset var community = "" />
        <cfset var getResId = "" />
        <cfset var getResName = "" />
        <cfset var getTaskType = "" />
        <cfset var rData = "" />

        <cfif CGI.SERVER_NAME neq "PROD_SERVER">
            <cfset auditLogURL = "http://DEV_LOG_URL/auditLog" />
            <cfset apiKey = "" />
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
                        "exclusions": exclusions,
                        "inclusions": inclusions,
                        "user": {
                            "employee_id": '#arguments.EmployeeID#',
                            "employee_ip": '#arguments.Employee_IP#'
                        },
                        "identifiers": {
                            "account_id": '#arguments.Account_ID#',
                            "community_name": '#community#',
                            "action": '#arguments.action#',
                            "application_id": 0,
                            "table_name": '#arguments.tableName#',
                            "area": '#arguments.area#',
                            "row_id": '#arguments.rowId#',
                            "resident_id": arguments.residentID,
                            "resident_name": '#resident#',
                            "event_id": '#arguments.event_id#'   
                        }
                    } 
                />
                
                <cfset var serializedSendData = serializeJSON(sendDataNew,'struct') />
                
                <!--- LOG_URL is set as a record in the C:\Windows\System32\drivers\etc\hosts file on the computer  --->
                <cfhttp method="POST" url="#auditLogURL#" result="rData" resolveurl="true">
                    <cfhttpparam type="header" name="Content-Type" value="application/json">
                    <cfhttpparam type="header" name="Accept" value="application/json">
                    <cfhttpparam type="header" name="Authorization" value="Api-Key #apiKey#">
                    <cfhttpparam type="body" name="on_order" value="#serializedSendData#">
                </cfhttp>

                <!--- We want to log any errors with reaching the audit log server or posting audit log information. --->
                <cfif rData.statusCode neq "200 OK">
                    <cfmail to="errors" from="errors" subject="Call to Audit Log failed with code #rData.statusCode# #cgi.server_name#" type="text" server="smtp.mandrillapp.com" username="ECP" password="#APPLICATION.mandrillPass#" port="587">
                        <cfoutput>
                            #serializedSendData#
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

        <cfset var auditLogURL = "https://LOG_URL/auditLog" />
        <cfset var apiKey = "=" />
        <cfif CGI.SERVER_NAME neq "PROD_SERVER">
            <cfset auditLogURL = "http://DEV_LOG_URL/auditLog" />
            <cfset apiKey = "" />
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

        <cfset var startDate2 = toUTC(startDate1, getTimeZone.IANA_TIMEZONE) />
        <cfset var endDate2 = toUTC(endDate1, getTimeZone.IANA_TIMEZONE) />

        <cfset var startDate = DateTimeFormat(startDate2, 'yyyy-mm-dd HH:nn:ss')>
        <cfset var endDate = DateTimeFormat(endDate2, 'yyyy-mm-dd HH:nn:ss')>
        <!--- Get the Data --->
        <cfhttp method="GET" url="#auditLogURL#" result="rData" resolveurl="true">
            <cfhttpparam type="header" name="Content-Type" value="application/json">
            <cfhttpparam type="header" name="Accept" value="application/json">
            <cfhttpparam type="header" name="Authorization" value="Api-Key #apiKey#">
            <cfhttpparam type="url" name="account_id" value="#arguments.account_id#">
            <cfif structKeyExists(arguments, "action")>
                <cfhttpparam type="url" name="action" value="#arguments.action#">
            </cfif>
            <cfif structKeyExists(arguments, "start_date")>
                <cfhttpparam type="url" name="start_date" value="#startDate#">
            </cfif>
            <cfif structKeyExists(arguments, "end_date")>
                <cfhttpparam type="url" name="end_date" value="#endDate#">
            </cfif>
        </cfhttp>

        <cfif rData.statusCode eq "200 OK" and isJSON(rData.FileContent)>
            <cfset results = deserializeJSON(rData.FileContent) />

            <!--- Let's build a query out of our data that we display for the list. This will allow us to group by whatever --->
            
            <cfloop from="1" to="#ArrayLen(results)#" index="i">
                <cfset QueryAddRow(auditLogQuery) />
                <cfset QuerySetCell(auditLogQuery,"ACCOUNT_ID", results[i]["identifiers"]["account_id"]) />
                <cfset QuerySetCell(auditLogQuery,"EVENT_ID", results[i]["identifiers"]["event_id"]) />
                <cfset QuerySetCell(auditLogQuery,"DATE_TIME", results[i]["createdAt"]) />
                <cfset QuerySetCell(auditLogQuery,"EMPLOYEE_ID", results[i]["user"]["employee_id"]) />
                <cfset QuerySetCell(auditLogQuery,"RESIDENT_ID", results[i]["identifiers"]["resident_id"]) />
                <cfset QuerySetCell(auditLogQuery,"ACTION", results[i]["identifiers"]["action"]) />
                <cfset QuerySetCell(auditLogQuery,"AREA", results[i]["identifiers"]["area"]) />
                <cfset QuerySetCell(auditLogQuery,"IP_ADDRESS", results[i]["user"]["employee_ip"]) />
                <cfset QuerySetCell(auditLogQuery,"JSON", serializeJSON(results[i])) />
                <cfset QuerySetCell(auditLogQuery,"OGDATE", results[i]["createdAt"]) />
            </cfloop>
        </cfif>

        <cfset success = (rData.statusCode eq "200 OK") ? true : false />

        <cfset returnStruct = structNew() />
        <cfset returnStruct.auditLogQuery = auditLogQuery />
        <cfset returnStruct.success = success />

        <!--- We want to log any errors with retrieving audit log information.  If there is an error when opening the audit log, we will display an error message. --->
        <cfif !success>
            <cfset theCFCATCH = structNew() />
            <cfset theCFCATCH["message"] = "Audit log returned #rData.statusCode#" />
            <cfinvoke component="#REQUEST.mapping#.cfc.extendedcarepro.errors" method="logError" returnVariable="errorId">
                <cfinvokeargument name="theCFCATCH" value="#theCFCATCH#">
            </cfinvoke>
            <cfset returnStruct.errorId = errorId />
        </cfif>

        <cfreturn returnStruct />
    </cffunction>

    <cfscript>
        function toUTC( required time, tz = "America/New_York" ){
            var timezone = createObject("java", "java.util.TimeZone").getTimezone( tz );
            var ms = timezone.getOffset( getTickCount() ); //get this timezone's current offset from UTC
            var seconds = ms / 1000;
            return dateAdd( 's', -1 * seconds, time );
        }
    </cfscript>

    <cffunction name="qryAuditLogDetails" access="public" returntype="any" output="false" hint="Calls API for changes that were logged ">
        <cfargument name="account_id" type="numeric" required="yes" />
        <cfargument name="event_id" type="string" required="yes" />

        <cfset var rData = "" />
        <cfset var results = ArrayNew(1) /> 

        <cfset var auditLogURL = "https://LOG_URL/auditLog" />
        <cfset var apiKey = "=" />
        <cfif CGI.SERVER_NAME neq "PROD_SERVER">
            <cfset auditLogURL = "http://DEV_LOG_URL/auditLog" />
            <cfset apiKey = "" />
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

        <!--- Get the Data --->
        <cfhttp method="GET" url="#auditLogURL#" result="rData" resolveurl="true">
            <cfhttpparam type="header" name="Content-Type" value="application/json">
            <cfhttpparam type="header" name="Accept" value="application/json">
            <cfhttpparam type="header" name="Authorization" value="Api-Key #apiKey#">
            <cfhttpparam type="url" name="account_id" value="#arguments.account_id#">
        </cfhttp>

        <cfif rData.statusCode eq "200 OK" and isJSON(rData.FileContent)>
            <cfset results = deserializeJSON(rData.FileContent) />
        </cfif>
       
        <cfreturn results />

    </cffunction>

    <cffunction name="buildLogDates" output="false" access="public" returnType="struct" hint="Audit log report calls this function to get dates associated with options">
		<cfargument name="auditRange" type="numeric" required="true" />

		<cfset var dateStruct = structNew() />
		<cfset dateStruct.auditStart = '' />
		<cfset dateStruct.auditEnd = '' />
		<cfset dateStruct.thisQuarterStart = '' />
		<cfset dateStruct.thisQuarterEnd = '' />
		<cfset dateStruct.lastQuarterStart = '' />
		<cfset dateStruct.lastQuarterEnd = '' />

		<cfset var currentDate = application.obj.user.getUserTime() />
		<cfset dateStruct.thisMonthStart = dateFormat(currentDate,'mm/01/yyyy') />
		<cfset var endDay = daysInMonth(dateStruct.thisMonthStart) />
		<cfset dateStruct.thisMonthEnd = dateFormat(dateStruct.thisMonthStart,'mm/#endDay#/yyyy') />

		<cfset dateStruct.lastMonthStart = dateFormat(dateAdd('m',-1,currentDate),'mm/01/yyyy') />
		<cfset endDay = daysInMonth(dateStruct.lastMonthStart) />
		<cfset dateStruct.lastMonthEnd = dateFormat(dateStruct.lastMonthStart,'mm/#endDay#/yyyy') />

		<cfswitch expression="#quarter(currentDate)#">
			<cfcase value="1">
				<cfset dateStruct.thisQuarterStart = '01/01/#year(currentDate)#' />
				<cfset dateStruct.thisQuarterEnd = '03/31/#year(currentDate)#' />
			</cfcase>
			<cfcase value="2">
				<cfset dateStruct.thisQuarterStart = '04/01/#year(currentDate)#' />
				<cfset dateStruct.thisQuarterEnd = '06/30/#year(currentDate)#' />
			</cfcase>
			<cfcase value="3">
				<cfset dateStruct.thisQuarterStart = '07/01/#year(currentDate)#' />
				<cfset dateStruct.thisQuarterEnd = '09/30/#year(currentDate)#' />
			</cfcase>
			<cfcase value="4">
				<cfset dateStruct.thisQuarterStart = '10/01/#year(currentDate)#' />
				<cfset dateStruct.thisQuarterEnd = '12/31/#year(currentDate)#' />
			</cfcase>
		</cfswitch>

		<cfset var lastQuarterDate = dateAdd('q',-1,currentDate) />
		<cfswitch expression="#quarter(lastQuarterDate)#">
			<cfcase value="1">
				<cfset dateStruct.lastQuarterStart = '01/01/#year(lastQuarterDate)#' />
				<cfset dateStruct.lastQuarterEnd = '03/31/#year(lastQuarterDate)#' />
			</cfcase>
			<cfcase value="2">
				<cfset dateStruct.lastQuarterStart = '04/01/#year(lastQuarterDate)#' />
				<cfset dateStruct.lastQuarterEnd = '06/30/#year(lastQuarterDate)#' />
			</cfcase>
			<cfcase value="3">
				<cfset dateStruct.lastQuarterStart = '07/01/#year(lastQuarterDate)#' />
				<cfset dateStruct.lastQuarterEnd = '09/30/#year(lastQuarterDate)#' />
			</cfcase>
			<cfcase value="4">
				<cfset dateStruct.lastQuarterStart = '10/01/#year(lastQuarterDate)#' />
				<cfset dateStruct.lastQuarterEnd = '12/31/#year(lastQuarterDate)#' />
			</cfcase>
		</cfswitch>

		<cfset dateStruct.ytdStart = dateFormat(currentDate,'01/01/yyyy') />
		<cfset dateStruct.ytdEnd = dateFormat(currentDate,'mm/dd/yyyy') />

		<cfset var lastYear = Year(currentDate) -1 />
		<cfset dateStruct.lastYearStart = '01/01/#lastYear#' />
		<cfset dateStruct.lastYearEnd = '12/31/#lastYear#' />

        <cfset var today = dateFormat(currentDate,'mm/dd/yyyy') />
        <cfset dateStruct.todayStart = today />
        <cfset dateStruct.todayEnd = today />

        <cfset dateStruct.thisWeekStart = dateFormat(today - DayOfWeek(today ) + 1, 'mm/dd/yyyy') />
        <cfset dateStruct.thisWeekEnd = dateFormat(today + (7 - DayOfWeek( today )), 'mm/dd/yyyy') />

        <cfset var dtLastWeek = (Fix( Now() ) - 7) />
        <cfset dateStruct.lastWeekStart = dateFormat(dtLastWeek - DayOfWeek( dtLastWeek ) + 1, 'mm/dd/yyyy') />
        <cfset dateStruct.lastWeekEnd = dateFormat(dateStruct.lastWeekStart + 6, 'mm/dd/yyyy') />

		<cfswitch expression="#arguments.auditRange#">
			<cfcase value="1">
				<cfset dateStruct.auditStart = dateStruct.thisMonthStart />
				<cfset dateStruct.auditEnd = dateStruct.thisMonthEnd />
			</cfcase>
			<cfcase value="2">
				<cfset dateStruct.auditStart = dateStruct.lastMonthStart />
				<cfset dateStruct.auditEnd = dateStruct.lastMonthEnd />
			</cfcase>
			<cfcase value="3">
				<cfset dateStruct.auditStart = dateStruct.thisQuarterStart />
				<cfset dateStruct.auditEnd = dateStruct.thisQuarterEnd />
			</cfcase>
			<cfcase value="4">
				<cfset dateStruct.auditStart = dateStruct.lastQuarterStart />
				<cfset dateStruct.auditEnd = dateStruct.lastQuarterEnd />
			</cfcase>
			<cfcase value="5">
				<cfset dateStruct.auditStart = dateStruct.ytdStart />
				<cfset dateStruct.auditEnd = dateStruct.ytdEnd />
			</cfcase>
			<cfcase value="6">
				<cfset dateStruct.auditStart = dateStruct.lastYearStart />
				<cfset dateStruct.auditEnd = dateStruct.lastYearEnd />
			</cfcase>
			<cfcase value="7">
				<cfset dateStruct.auditStart = '' />
				<cfset dateStruct.auditEnd = '' />
			</cfcase>
            <cfcase value="8">
				<cfset dateStruct.auditStart = dateStruct.todayStart />
				<cfset dateStruct.auditEnd = dateStruct.todayEnd />
			</cfcase>
            <cfcase value="9">
				<cfset dateStruct.auditStart = dateStruct.thisWeekStart />
				<cfset dateStruct.auditEnd = dateStruct.ThisWeekEnd />
			</cfcase>
            <cfcase value="10">
				<cfset dateStruct.auditStart = dateStruct.lastWeekStart />
				<cfset dateStruct.auditEnd = dateStruct.lastWeekEnd />
			</cfcase>
		</cfswitch>

		<cfreturn dateStruct />
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