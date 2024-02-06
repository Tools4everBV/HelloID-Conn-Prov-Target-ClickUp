#################################################
# HelloID-Conn-Prov-Target-ClickUp-Create
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-ClickUpError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }

        try {
            if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
                $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
                $httpErrorObj.FriendlyMessage = ($ErrorObject.ErrorDetails.Message | ConvertFrom-Json)
            } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if ($null -ne $streamReaderResponse) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        } catch {
            $httpErrorObj.FriendlyMessage = "Received an unexpected response. The JSON could not be converted, error: [$($_.Exception.Message)]. Original error from web service: [$($ErrorObject.Exception.Message)]"
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Verify if [actionContext.Data.email] has a value
    if ([string]::IsNullOrEmpty($($actionContext.Data.email))) {
        throw 'Mandatory attribute [Person.Accounts.MicrosoftActiveDirectory.mail] is empty. Please make sure it is correctly mapped'
    }

    Write-Verbose 'Acquiring access_token'
    $splatRetrieveTokenParams = @{
        Uri         = "$($actionContext.Configuration.BaseUrl)/api/v2/oauth/token?client_id=$($actionContext.Configuration.ClientId)&client_secret=$($actionContext.Configuration.ClientSecret)&code=$($actionContext.Configuration.Code)"
        Method      = 'POST'
    }
    $responseToken = Invoke-RestMethod @splatRetrieveTokenParams -Verbose:$false

    # Set authorization header
    $splatParams = @{
        Headers = @{
            Authorization = "$($responseToken.access_token)"
        }
    }

    # Verify if a user must be either [created and correlated] or just [correlated]
    # First step is to retrieve all authenticated workspaces
    $splatParams['Uri'] = "$actionContext.Configuration.BaseUrl/api/v2/team"
    $splatParams['Method'] = 'GET'
    $authenticatedWorkspaces = Invoke-RestMethod @splatParams -Verbose:$false

    # Filter out the team where the team_id equals the team_id from the field mapping
    $team = $authenticatedWorkspaces.teams | Where-Object {$_.id -eq $($actionContext.Data.team_id)}
    if ($null -eq $team){
        throw "Workspace team with id: [$($actionContext.Data.team_id)] could not be found"
    }

    # Filter the account where the email equals the person.Accounts.MicrosoftActiveDirectory.mail
    $correlatedAccount = $team.members | Where-Object {$_.email -eq $($actionContext.Data.email)}
    if ($null -eq $correlatedAccount) {
        $action = 'CreateAccount'
        $outputContext.AccountReference = 'Currently not available'
    } else {
        $action = 'CorrelateAccount'
        $outputContext.AccountReference = $correlatedAccount.id
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Verbose "[DryRun] $action ClickUp account for: [$($personContext.Person.DisplayName)], will be executed during enforcement"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'CreateAccount' {
                Write-Verbose 'Creating and correlating ClickUp account'

                # Make sure to test with special characters and if needed; add utf8 encoding.
                $splatParams['Uri'] = "$($actionContext.Configuration.BaseUrl)/api/v2/$($actionContext.Data.team_id)/user"
                $splatParams['Method'] = 'POST'
                $splatParams['Body'] = @{
                    email          = $($actionContext.Data.email)
                    admin          = $($actionContext.Data.admin)
                    custom_role_id = $($actionContext.Data.custom_role_id)
                } | ConvertTo-Json
                $responseInviteUser = Invoke-RestMethod @splatParams -Verbose:$false
                $outputContext.AccountReference = $responseInviteUser.id
                $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)"
                break
            }

            'CorrelateAccount' {
                Write-Verbose 'Correlating ClickUp account'
                $outputContext.AccountReference = $correlatedAccount.id
                $outputContext.AccountCorrelated = $true
                $auditLogMessage = "Correlated account: [$($correlatedAccount.ExternalId)] on field: [$($correlationField)] with value: [$($correlationValue)]"
                break
            }
        }

        $outputContext.success = $true
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = $action
                Message = $auditLogMessage
                IsError = $false
            })
    }
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-ClickUpError -ErrorObject $ex
        $auditMessage = "Could not $action ClickUp account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not $action ClickUp account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
