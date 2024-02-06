##################################################
# HelloID-Conn-Prov-Target-ClickUp-Delete
# PowerShell V2
##################################################

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
                $httpErrorObj.FriendlyMessage =  ($ErrorObject.ErrorDetails.Message | ConvertFrom-Json)
            } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if($null -ne $streamReaderResponse){
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
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
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

    Write-Verbose "Verifying if a ClickUp account for [$($personContext.Person.DisplayName)] exists"
    $splatParams['Uri'] = "$($actionContext.Configuration.BaseUrl)/api/v2/$($actionContext.Data.teamId)/$($actionContext.AccountReference)"
    $splatParams['Method'] = 'GET'
    $correlatedAccount = Invoke-RestMethod @splatParams -Verbose:$false
    if ($null -ne $correlatedAccount) {
        $action = 'DeleteAccount'
        $dryRunMessage = "Delete ClickUp account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] will be executed during enforcement"
    } else {
        $action = 'NotFound'
        $dryRunMessage = "ClickUp account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Verbose "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'DeleteAccount' {
                Write-Verbose "Deleting ClickUp account with accountReference: [$($actionContext.References.Account)]"
                $splatParams['Uri'] = "$actionContext.Configuration.BaseUrl/api/v2/$($actionContext.Data.teamId)/$($actionContext.AccountReference)"
                $splatParams['Method'] = 'DELETE'
                $response = Invoke-RestMethod @splatParams
                if ($response.StatusCode -eq 200){
                    $outputContext.Success = $true
                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = 'Delete account was successful'
                        IsError = $false
                    })
                    break
                }
            }

            'NotFound' {
                $outputContext.Success  = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "ClickUp account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
                    IsError = $false
                })
                break
            }
        }
    }
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-ClickUpError -ErrorObject $ex
        $auditMessage = "Could not delete ClickUp account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not delete ClickUp account. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
        Message = $auditMessage
        IsError = $true
    })
}
