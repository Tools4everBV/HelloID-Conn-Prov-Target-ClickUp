
# HelloID-Conn-Prov-Target-ClickUp

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.


<p align="center">
  <img src="./Logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-ClickUp](#helloid-conn-prov-target-clickup)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Provisioning PowerShell V2 connector](#provisioning-powershell-v2-connector)
      - [Correlation configuration](#correlation-configuration)
      - [Field mapping](#field-mapping)
    - [Connection settings](#connection-settings)
    - [Prerequisites](#prerequisites-1)
    - [Remarks](#remarks)
      - [`team_id`](#team_id)
      - [`custom_role_id`](#custom_role_id)
      - [Invite only](#invite-only)
      - [Validation based on `email`](#validation-based-on-email)
      - [Error handling](#error-handling)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-ClickUp_ is a _target_ connector. _ClickUp_ provides a set of REST API's that allow you to programmatically interact with its data.

The following lifecycle actions are available:

| Action     | Description                          |
| ---------- | ------------------------------------ |
| create.ps1 | PowerShell _create_ lifecycle action |
| delete.ps1 | PowerShell _delete_ lifecycle action |

## Getting started

### Prerequisites

Before implementing this connector, make sure the following requirements are met:

- [ ] Access to the _ClickUp_ API.
  - [ ] PersonalToken (generated for the admin account wihtin ClickUp)
  - [ ] Base URL is always: 'https://api.clickup.com'
- [ ] The `team_id` of the team for which the users will be invited. This value is needed in the field mapping.
- [ ] The `role_id` with name _member_. This value is needed in the field mapping.

### Provisioning PowerShell V2 connector

_HelloID-Conn-Prov-Target-ClickUp_ is a PowerShell V2 connector. Albeit, there are a few changes.

#### Correlation configuration

Since there's no requirement for user management and because validation is based on the `email` address, the correlation configuration is not implemented within the _HelloID-Conn-Prov-Target-ClickUp_ connector.

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

#### Field mapping

The field mapping can be imported using the _fieldMapping.json_ file.

### Connection settings

The following settings are required to connect to the API.

| Setting       | Description                                  | Mandatory |
| ------------- | -------------------------------------------- | --------- |
| PersonalToken | PersonalToken to connect to the ClickUp API. | Yes       |
| BaseUrl       | The URL to the API.                          | Yes       |

### Prerequisites

- [ ] The _ClickUp_ API credentials.
- [ ] Fixed value for `team_id`.
- [ ] Fixed value for [`custom_role_id`.](#custom_role_id) (optional)

### Remarks

#### `team_id`

The `team_id` is equal for all accounts _created in_ or _invited to_ _ClickUp_.

>[!TIP]
> The value must be retrieved __before__ implementing this connector by making an API call to: https://clickup.com/api/clickupreference/operation/GetAuthorizedTeams/.

#### `custom_role_id`

The API call for inviting users to _ClickUp_ requires the `custom_role_id`. This is a __mandatory__ property. As with the `team_id`, its value is equal for all accounts. The `custom_role_name` is _member_.

>[!TIP]
>The value must be retrieved __before__ implementing this connector by using the code specifed below.
> ```powershell
> # Script to find the id for a role with name 'member'.
> # API call: https://clickup.com/api/clickupreference/operation/GetCustomRoles/
> # -----------------------------------------------------------------------------
>
> # Configuration
> $baseUrl      = ''
> $clientId     = ''
> $clientSecret = ''
> $code         = ''
> $team_id      = ''
>
> $splatRetrieveTokenParams = @{
>        Uri         = "$baseUrl/api/v2/oauth/token?client_id=$clientId&client_secret=$clientSecret&code=$code"
>        Method      = 'POST'
>    }
> $responseToken = Invoke-RestMethod @splatRetrieveTokenParams -Verbose:$false
>
> # Set authorization header
> $splatParams = @{
>     Headers = @{
>         Authorization = "$($responseToken.access_token)"
>     }
> }
>
> # First step is to retrieve all roles
> $splatParams['Uri'] = "$baseUrl/api/v2/team/$team_id/customroles"
> $splatParams['Method'] = 'GET'
> $allRoles = Invoke-RestMethod @splatParams
>
> # Filter out the role where the name of the role matches with 'member'.
> $roleToAssign = $allRoles | Where-Object {$_.name -eq 'member'}
>
> # Get the role_id property
> $roleToAssign.id
> ```

#### Invite only

The _create_ lifecycle action doesn't actually create an account but instead, makes an API call that will ultimately result in an _invite_ mail being send to the persons email address.

#### Validation based on `email`

Because _ClickUp_ doesn't contain an `employeeId` field, it's not possible to validate the account based on this field. The only _reliable_ field we can validate on, is the `email` field. Unfortunately, _ClickUp_ also does not provide an API call to retrieve a single account. (or use filters).

The validation process is currently implemented as follows:

1. Retrieve all authenticated workspaces using API call: https://clickup.com/api/clickupreference/operation/GetAuthorizedTeams/ This will return an object that contains __all__ teams including the team members.
2. The next step is to filter out the team where the `team_id` equals the `team_id` specified in the field mapping.
3. The final step is filter out the members. If the `email` property from a specific member matches with the `Person.Accounts.MicrosoftActiveDirectory.mail` a correlated account if found.

#### Error handling

During development, a test environment was not available. Therefore, error handling is not tested and requires modification.

> [!TIP]
> The connector is developed based on the latest available API documentation which can be found on: https://clickup.com/api/

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
