# Collect information about documents in Document Management via the IDM ION API.
# 2025-04-17 Version containing major update on syntax and progress indicator added for includeDetails.
# 2025-05-16 Version Added tenant name to output filename, added more details and output file having document properties for includeDetails.
# 2025-05-16 Version Added option to collect one Document Type only.
# 2025-05-16 Version Added option to collect all attributes values for documents.
# 2025-06-19 Version Added option filter older than date documents, and added few minor corrections and improvements.

<#
.SYNOPSIS
	Collect information about Documents in Infor Document Management.
	Default is to count Documents per Document Type for each state: Active, Archived and Deleted. This takes few minutes typically.
	Output is a csv file having all documents types and their numbers named: '<Tenant>_IDM-Documents-Count.csv'
	Use the includeDetails switch to include information about the Active documents having no file attached and count the total size of all Active documents. This takes considerable more time!
	The information about missing files is stored in a csv file named: '<Tenant>_IDM-Documents-MissingFiles.csv'
	Use the includeAttributes switch to include all Single-value attributes per Document on top of the includeDetails.
	The detailed information is stored in a csv file per Document Type named: '<Tenant>_IDM-Documents-details-<Document Name>.csv'
	The MDS_ID column is present in case the option Use Unique ID is active for that Document Type.
	The fieldSeparator can be defined: ';', ',', '|', default = ';'
	The priorToCreatedTS can be used to read only documents based on the TimeStamp they are initially created.
.DESCRIPTION
	Preparation by user
	Required Security Roles: IDM-User & IDM-SuperUser (to count Deleted Documents!)
	1.	Create Authorized App in ION API of type Backend Service, link it to a user with sufficient Security Roles to call APIs, store this in a safe place as it contains sensitive data
	2.	Download ION API file *.ionapi file
	3.	Set your ExecutionPolicy for example: set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser
	4.	Start this script with the corresponding parameters
.EXAMPLE
	Start the PowerShell script selecting the required methode.
	To count the documents per Document Type:
	.\Read-IDMDocumentInformation.ps1 -ionapiFile '.\YourTenant.ionapi'
	To count the documents per Document Type including the Active documents having no file attached and the total size of all Active documents.
	.\Read-IDMDocumentInformation.ps1 -ionapiFile '.\YourTenant.ionapi' -includeDetails
	To include all attributes per document, this includes the details too.
	.\Read-IDMDocumentInformation.ps1 -ionapiFile '.\YourTenant.ionapi' -includeAttributes
	To collect data for one Document Type only, specify the Name in IDM, instead of the Display name.
	.\Read-IDMDocumentInformation.ps1 -ionapiFile '.\YourTenant.ionapi' -specificDocumentType 'Item_Images'
	To define a specific field separator to be used for the csv, ';', ',', '|', default = ';'
	.\Read-IDMDocumentInformation.ps1 -ionapiFile '.\YourTenant.ionapi' -fieldSeparator ','
	To define a specific prior to Date yyyy-mm-dd:
	This will use XQuery like: /OPL_Templates[@CREATETS < "2025-06-16T23:59:59.999Z"] SORTBY(@LASTCHANGEDTS DESCENDING)
	.\Read-IDMDocumentInformation.ps1 -ionapiFile '.\YourTenant.ionapi' -priorToCreatedTS 2025-06-16
#>

#region ParametersMain
param (
	[string]
	[Parameter(Mandatory,HelpMessage='The *.ionapi file downloaded from ION API of type Backend Service.')]
		$ionapiFile,
	[switch]
	[Parameter(HelpMessage='To include information about the Active documents having no file attached and the total size of all Active documents.')]
		$includeDetails,
	[switch]
	[Parameter(HelpMessage='To include values of attributes for all Active documents. This also activates includeDetails')]
		$includeAttributes,
	[string]
	[Parameter(HelpMessage='Select information for one Document Type only, specify the IDM Name, instead of the Display name')]
		$specificDocumentType,
	[string]
	[Parameter(HelpMessage='The required separator ";", ",", "|", default = ;')]
	[ValidateSet(";",",","|")]
		$fieldSeparator = ";",
	[string]
	[Parameter(HelpMessage='The created Date filter delecting older than yyyy-mm-dd. T23:59:59.999Z will be appended ex. 2025-03-21 ')]
	[ValidatePattern('^\d{4}\-\d{2}\-\d{1,2}$')]
		$priorToCreatedTS = "DEFAULT"
)
#endregion ParametersMain

#region FunctionDefinitions
function Read-ionapiFile {
	<#
	.SYNOPSIS
		Read the *.ionapi file of type Backend Service to extract the details.
	.DESCRIPTION
		Prerequisite: First create Authorized App in ION API of type Backend Service and download ION API file *.ionapi file
		The *.ionapi file is checked if it exists and contains a correctly formed json
		Return with the json object that is read.
	#>

    [CmdletBinding()]
    [OutputType("System.Object")]

	# Define parameters
	param (
		[string]
		[Parameter(Mandatory,HelpMessage='The *.ionapi file downloaded from ION API of type Backend Service.')]
			$ionapiFile
	)
	# Process the *.ionapi file
	process {
		if (Test-Path $ionapiFile -PathType Leaf) {
			try {
				$result = (Get-Content $ionapiFile | ConvertFrom-Json)
			}
			catch{
				Write-Verbose -Message ('Error: No correct *.ionapi file found, please provide correct *.ionapi file')
				Return $null
			}
		}
		else {
			Write-Verbose -Message ('Error: No *.ionapi file found, please provide *.ionapi file')
			Return $null
		}
		Return $result
	}
}

function Request-IONAPIToken {
	<#
	.SYNOPSIS
		Requests the access and refresh token based on the ionapi json object in the *.ionapi file
	.DESCRIPTION
		Calling the token URI pu + ot
			pu   : https://mingle-sso<your tenant>:443/YOUR_TENANT/as/
			ot   : token.oauth2
		The ContentType is set to x-www-form-urlencoded
	.PARAMETER
		The input is the json object from the *.ionapi, based on this a body is constructed
	.OUTPUTS
		The output is the json object response containing a refresh_token and an access_token, this is used in the header as Bearer token for the ION API calls
	#>

    [CmdletBinding()]
    [OutputType("System.Object")]

	# Define parameters
	param (
		[object]
		[Parameter(Mandatory,HelpMessage='The ionapi json content downloaded from ION API')]
			$ionapiObject
	)
	# Process the token request
	process {
		# set local parameters
		$contentOauth		= 'application/x-www-form-urlencoded'			# used for OAuth requests
		$tokenUri			= $ionapiObject.pu + $ionapiObject.ot
		# Create the body to get Bearer Token required for ION API based on the elements in the *.ionapi
		if ( $ionapiObject.ti -eq 'infor' ) {
			# if Tenant = infor then we run on-premises and scope can not be used
			$body = @{
				grant_type		= 'password'
				client_id		= $ionapiObject.ci
				client_secret	= $ionapiObject.cs
				username		= $ionapiObject.saak
				password		= $ionapiObject.sask
			#	scope			= ''
			}
		} else {
			$body = @{
				grant_type		= 'password'
				client_id		= $ionapiObject.ci
				client_secret	= $ionapiObject.cs
				username		= $ionapiObject.saak
				password		= $ionapiObject.sask
				scope			= ''
			}
		}
		# Request access_token and refresh_token
		try {
			$OAuthResult = Invoke-RestMethod -URI $tokenUri -Method Post -Body $body -ContentType $contentOauth
		}
		catch {
			Write-Verbose -Message  ('Error: ' + $_.Exception.Message)
			Write-Verbose -Message  ('Error: Check the *.ionapi file or download new using proper Service Account.')
			Return $null
		}
		Return $OAuthResult
	}
}

function Request-NewAccessToken {
	<#
	.SYNOPSIS
		Refreshes the token when it has been expired
	.DESCRIPTION
		Calling the token URI pu + ot
			pu   : https://mingle-sso<your tenant>:443/YOUR_TENANT/as/
			ot   : token.oauth2
		The ContentType is set to x-www-form-urlencoded
		The Header does not require the Bearer token
		Remark: it does not contain the original refresh_token itself, only the token originally requested contains that refresh_token
	.PARAMETER
		The input is the json object from the *.ionapi, based on this a body is constructed
		The input is the oauthObject containing the current OAuth token information
	.OUTPUTS
		The response contains a new access_token, this is used in the new header as Bearer token
	#>

    [CmdletBinding()]
    [OutputType("System.Object")]

	# Define parameters
	param (
		[object]
		[Parameter(Mandatory,HelpMessage='The ionapi json content downloaded from ION API')]
			$ionapiObject,
		[object]
		[Parameter(Mandatory,HelpMessage='The OAuth object containing the token information')]
			$oauthObject
	)
	# Process the request for new access token
	process {
		# set local parameters
		$contentOauth		= 'application/x-www-form-urlencoded'			# used for OAuth requests
		$tokenUri			= $ionapiObject.pu + $ionapiObject.ot
		if ($oauthObject.refresh_token) {
			# If a refresh token was provided in the $oauthObject.refresh_token, only filled when 'Issue Refresh Token' is active
			# Create the body to based on the refreshToken and the elements in the *.ionapi
			$refreshTokenBody = @{
				refresh_token	= $oauthObject.refresh_token
				client_id		= $ionapiObject.ci
				client_secret	= $ionapiObject.cs
				grant_type		= 'refresh_token'
			}
			# Create the header for the OAuth request using the access_token
			$headers	= @{
					'Accept' = 'application/json'
			}
			# Request new access_token and refresh_token
			try {
				Write-Verbose -Message  ('Request new Access token using Refresh token.')
				$refreshOAuth = Invoke-RestMethod -URI $tokenUri -Method Post -body $refreshTokenBody -Headers $headers -ContentType $contentOauth
			}
			catch {
				Write-Verbose -Message  ('Using Refresh token failed, request new Refresh token including Access token.')
				$refreshOAuth = ( Request-IONAPIToken -ionapiObject $ionapiObject )
			}
		} else {
			# Request new access token
			Write-Verbose -Message  ('Request new Access token.')
			$refreshOAuth = ( Request-IONAPIToken -ionapiObject $ionapiObject )
		}
		Return $refreshOAuth
	}
}
#endregion FunctionDefinitions

#region IDMFunctionDefinitions
function Test-IDMValidity {
	<#
	.SYNOPSIS
		Check if ION API for IDM is valid
	.DESCRIPTION
		Calling the IDM API /IDM/api/connection/validate
	.PARAMETER
		The ionapiObject contains the json object from the *.ionapi, based on this the URI is constructed
		The Oauth object contains the access_token required for the header
	.OUTPUTS
		The response contains the validity of the connection to IDM
	#>

    [CmdletBinding()]
    [OutputType("System.Object")]

	#
	# Define input parameters
	#
	param (
		[object]
		[Parameter(Mandatory,HelpMessage='The ionapi json content downloaded from ION API')]
			$ionapiObject,
		[object]
		[Parameter(Mandatory,HelpMessage='The OAuth object containing the token information')]
			$oauthObject
	)
	#
	# Process reading the IDM
	#
	process {
		# set local parameters
		$validateIDMUri		= $ionapiObject.iu + '/' + $ionapiObject.ti + '/IDM/api/connection/validate'
		$contentJson		= 'application/json'
		$headers			= @{
			'Authorization' = 'Bearer ' + $oauthObject.access_token;
			'Accept' = 'application/json'
		}
		#
		# Create the body to based on the refreshToken and the elements in the *.ionapi
		#
		try {
			$response    = Invoke-RestMethod -URI $validateIDMUri -Method Get -ContentType $contentJson -Headers $headers
		}
		catch{
			Write-Verbose -Message  ('Error: ' + $_.Exception.Message)
			Write-Verbose -Message ('Error: Not able to validate the IDM ION API')
			Return $null
		}
		if ($response) {
			Write-Verbose -Message ('Test-IDMValidity: IDM validation check results	: ' + $response.validated)
			Return $response
		} else {
			Write-Verbose -Message ('Test-IDMValidity: Not able to validate the IDM ION API')
			Return $null
		}
	}
}

function Test-IDMLogin {
	<#
	.SYNOPSIS
		Check if ION API for IDM is available for login
	.DESCRIPTION
		Calling the IDM API /IDM/api/connection/login
	.PARAMETER
		The ionapiObject contains the json object from the *.ionapi, based on this the URI is constructed
		The Oauth object contains the access_token required for the header
	.OUTPUTS
		The response contains the validity of the connection/login to IDM
	#>

    [CmdletBinding()]
    [OutputType("System.Object")]

	#
	# Define input parameters
	#
	param (
		[object]
		[Parameter(Mandatory,HelpMessage='The ionapi json content downloaded from ION API')]
			$ionapiObject,
		[object]
		[Parameter(Mandatory,HelpMessage='The OAuth object containing the token information')]
			$oauthObject
	)
	#
	# Process reading the IDM
	#
	process {
		# set local parameters
		$loginIDMUri		= $ionapiObject.iu + '/' + $ionapiObject.ti + '/IDM/api/connection/login'
		$contentXML		= 'application/xml'
		$headers			= @{
			'Authorization' = 'Bearer ' + $oauthObject.access_token;
			'Accept' = 'application/xml'
		}
		#
		# Create the body to based on the refreshToken and the elements in the *.ionapi
		#
		try {
			$response    = Invoke-RestMethod -URI $loginIDMUri -Method Get -ContentType $contentXML -Headers $headers
		}
		catch{
			Write-Verbose -Message  ('Error: ' + $_.Exception.Message)
			Write-Verbose -Message ('Error: Not able to login to the IDM ION API')
			Return $null
		}
		if ($response) {
			Write-Verbose -Message ('Test-IDMLogin: IDM connection/login check results	: ' + $response.validated)
			Return $response
		} else {
			Write-Verbose -Message ('Test-IDMLogin: Not able to connection/login to the IDM ION API')
			Return $null
		}
	}
}

function Read-IDMEntity {
	<#
	.SYNOPSIS
		Read the datamodel entities available in IDM
	.DESCRIPTION
		Calling the IDM API /IDM/api/datamodel/entities
	.PARAMETER
		The ionapiObject contains the json object from the *.ionapi, based on this the URI is constructed
		The Oauth object contains the access_token required for the header
	.OUTPUTS
		The response contains the list of available entities in IDM
	#>

    [CmdletBinding()]
    [OutputType("System.Object")]

	#
	# Define input parameters
	#
	param (
		[object]
		[Parameter(Mandatory,HelpMessage='The ionapi json content downloaded from ION API')]
			$ionapiObject,
		[object]
		[Parameter(Mandatory,HelpMessage='The OAuth object containing the token information')]
			$oauthObject
	)
	#
	# Process reading the IDM
	#
	process {
		# set local parameters
		$entitiesDocIDMUri 	= $ionapiObject.iu + '/' + $ionapiObject.ti + '/IDM/api/datamodel/entities'
		$contentJson		= 'application/json'
		$headers			= @{
			'Authorization' = 'Bearer ' + $oauthObject.access_token;
			'Accept' = 'application/json'
		}
		#
		# Call the ION API to get all details of all entities in IDM
		#
		try {
			$entityList    = Invoke-RestMethod -URI $entitiesDocIDMUri -Method Get -ContentType $contentJson -Headers $headers
		}
		catch{
			Write-Verbose -Message  ('Error: ' + $_.Exception.Message)
			Write-Verbose -Message ('Error: Not able to read the entityList via IDM ION API')
			Return $null
		}
		if ($entityList.entities.entity) {
			Write-Verbose -Message ('Read-IDMEntity: entityList contains ' + $entityList.entities.entity.count + ' entities')
			Return $entityList.entities.entity
		} else {
			Write-Verbose -Message ('Read-IDMEntity: entityList contains NO entities')
			Return $null
		}
	}
}

function Read-IDMEntityDetail {
	<#
	.SYNOPSIS
		Read the details of specific entity in IDM
	.DESCRIPTION
		Calling the IDM API /IDM/api/items/count
	.PARAMETER
		The ionapiObject contains the json object from the *.ionapi, based on this the URI is constructed
		The Oauth object contains the access_token required for the header
		The IDM entity object containing the information for that entity
		The response contains the updated entity object enriched with counted documents per type
	#>

    [CmdletBinding()]
    [OutputType("System.Object")]

	#
	# Define input parameters
	#
	param (
		[object]
		[Parameter(Mandatory,HelpMessage='The ionapi json content downloaded from ION API')]
			$ionapiObject,
		[object]
		[Parameter(Mandatory,HelpMessage='The OAuth object containing the token information')]
			$oauthObject,
		[object]
		[Parameter(Mandatory,HelpMessage='The IDM entity object containing the information for that entity')]
			$entityObject
	)
	#
	# Process reading the IDM
	#
	process {
		# set local parameters
		$countDocIDMUri 	= $ionapiObject.iu + '/' + $ionapiObject.ti + '/IDM/api/items/count'
		$contentJson		= 'application/json'
		$headers			= @{
			'Authorization' = 'Bearer ' + $oauthObject.access_token;
			'Accept' = 'application/json'
		}

		# Enrich the entityObject with three members to contain the number of documents per state
		$entityObject | Add-Member -NotePropertyName ActiveDocuments 	-NotePropertyValue 0
		$entityObject | Add-Member -NotePropertyName ArchivedDocuments	-NotePropertyValue 0
		$entityObject | Add-Member -NotePropertyName DeletedDocuments	-NotePropertyValue 0

		# In IDM Database the documents are stored in different tables depending on their state
		# Count the # of documents having state = Active for that entity
		$queryUri = $countDocIDMUri + '?%24query=%2F' + $entityObject.name + '&%24state=0'
		try {
			$countDocsActive	= Invoke-RestMethod -URI $queryUri -Method Get -ContentType $contentJson -Headers $headers
		}
		catch{
			Write-Verbose -Message  ('Error: ' + $_.Exception.Message)
			Write-Verbose -Message ('Error: Not able to count the documents for this entity via IDM ION API')
		}
		if ( $countDocsActive ) { $entityObject.ActiveDocuments 	= $countDocsActive.count }
		#
		# Count the # of documents having state = Archive for that entity
		$queryUri = $countDocIDMUri + '?%24query=%2F' + $entityObject.name + '&%24state=1'
		try {
			$countDocsArchived	= Invoke-RestMethod -URI $queryUri -Method Get -ContentType $contentJson -Headers $headers
		}
		catch{
			Write-Verbose -Message  ('Error: ' + $_.Exception.Message)
			Write-Verbose -Message ('Error: Not able to count the documents for this entity via IDM ION API')
		}
		if ( $countDocsArchived ) { $entityObject.ArchivedDocuments 	= $countDocsArchived.count }
		#
		# Count the # of documents having state = Delete for that entity
		$queryUri = $countDocIDMUri + '?%24query=%2F' + $entityObject.name + '&%24state=2'
		try {
			$countDocsDeleted	= Invoke-RestMethod -URI $queryUri -Method Get -ContentType $contentJson -Headers $headers
		}
		catch{
			Write-Verbose -Message  ('Error: ' + $_.Exception.Message)
			Write-Verbose -Message ('Error: Not able to count the documents for this entity via IDM ION API')
		}
		if ( $countDocsDeleted ) { $entityObject.DeletedDocuments 	= $countDocsDeleted.count }

		Return $entityObject
	}
}

function Get-IDMItemsSearch {
	<#
	.SYNOPSIS
		Search for items (by string)
	.DESCRIPTION
		Calling the IDM API /IDM/api/items/search
		Returns a document containing the items matching the query. An example of a query is /MDS_File[@MDS_Name="MyName"] which returns the items named "MyName" of the document type "MDS_Image". Note that it's also possible to call the post method with text/plain as parameter content type (when calling from outside this UI).
	.PARAMETER
		The ionapiObject contains the json object from the *.ionapi, based on this the URI is constructed
		The Oauth object contains the access_token required for the header
		The query parameter, containing the document type and additional query, e.g. /Images[@Name LIKE "Picture%"], /MDS_Documents' No leading ''/'' allowed that will be added later.
		The offset containing the Start index of the search. Use 0 for the first item.
		The limit containing the maximum number of returned items. Must be between 0 and 1000.
		The includeCount containing a boolean value (true/false) If a search count should be included in the result, including a count may result that the operation takes longer time to execute
		The state containing the document state to search for (0 = Active, 1 = Archived and 2 = Deleted).
	.OUTPUTS
		The response contains the list of available items in IDM in object format like:
		{
		  "items": {
			"searchXQuery": "/Images",
			"searchCount": "2",
			"item": [
			  {
				"filename": "Luigi 01.png",
				"size": "168227",
				"pid": "Images-9-2-LATEST",
	#>


    [CmdletBinding()]
    [OutputType("System.Object")]

	#
	# Define input parameters
	#
	param (
		[object]
		[Parameter(Mandatory,HelpMessage='The ionapi json content downloaded from ION API')]
			$ionapiObject,
		[object]
		[Parameter(Mandatory,HelpMessage='The OAuth object containing the token information')]
			$oauthObject,
		[string]
		[Parameter(Mandatory,HelpMessage='The Query parameter, containing the document type and additional query, e.g. Images[@Name LIKE "Picture%"], MDS_Documents, No leading ''/'' allowed ')]
			$query,
		[int32]
		[AllowNull()]
		[Parameter(Mandatory,HelpMessage='The Start index of the search. Use 0 for the first item.')]
			$offset,
		[int32]
		[ValidateRange(0,1000)]
		[AllowNull()]
		[Parameter(Mandatory,HelpMessage='The maximum number of returned items. Must be between 0 and 1000.')]
			$limit,
		[string]
		[ValidateSet("true", "false")]
		[Parameter(HelpMessage='A boolean value (true/false) If a search count should be included in the result, including a count may result that the operation takes longer time to execute')]
			$includeCount,
		[int32]
		[ValidateRange(0,2)]
		[Parameter(HelpMessage='The document state to search for (0 = Active, 1 = Archived and 2 = Deleted).')]
			$state
	)
	#
	# Process reading the IDM
	#
	process {
		# set local parameters
		$searchItemsIDMUri 	= $ionapiObject.iu + '/' + $ionapiObject.ti + '/IDM/api/items/search?'
		$searchItemsIDMUri	= $searchItemsIDMUri + '%24query=%2F' + $query + '&%24offset=' + $offset + '&%24limit=' + $limit
		if ( $includeCount -eq 'true') { $searchItemsIDMUri = $searchItemsIDMUri + '&%24includeCount=' + $includeCount }
		if ( $state ) { $searchItemsIDMUri = $searchItemsIDMUri + '&%24state=' + $state }
		Write-Verbose -Message ('Info: searchItemsIDMUri: ' + $searchItemsIDMUri)

		$contentJson		= 'application/json'
		$headers			= @{
			'Authorization' = 'Bearer ' + $oauthObject.access_token;
			'Accept' = 'application/json'
		}
		#
		# Call the ION API to get all details of all entities in IDM
		#
		try {
			$itemsList    = Invoke-RestMethod -URI $searchItemsIDMUri -Method Get -ContentType $contentJson -Headers $headers
		}
		catch{
			Write-Verbose -Message  ('Error: ' + $_.Exception.Message)
			Write-Verbose -Message ('Error: Not able to search items via IDM ION API, due to wrong query or any other error')
			Return $null
		}
		if ($itemsList.items.item) {
			Write-Verbose -Message ('Get-IDMItemsSearch: List of items contains ' + $itemsList.items.item.count + ' items in this selection')
			if ( $includeCount  -eq 'true' ) { Write-Verbose -Message ('Get-IDMItemsSearch: List of items contains ' + $itemsList.items.searchCount + ' items in total') }
			Return $itemsList.items
		} else {
			Write-Verbose -Message ('Get-IDMItemsSearch: List of items contains NO items')
			Return $null
		}
	}
}
#endregion IDMFunctionDefinitions

######################################################################################################################################################
# Main body
######################################################################################################################################################

#region ShowParameters
if ($priorToCreatedTS -ne 'DEFAULT') {
	$priorToCreatedDateTime = $priorToCreatedTS + 'T23:59:59.999Z'
	}

Write-Output ('Info: ION API File         -ionapiFile:           ' + $ionapiFile)
Write-Output ('Info: include Details      -IncludeDetails:       ' + $IncludeDetails)
Write-Output ('Info: include Attributes   -IncludeAttributes:    ' + $includeAttributes)
Write-Output ('Info: include Specifc Doc  -specificDocumentType: ' + $specificDocumentType)
Write-Output ('Info: prior to Created TS  -priorToCreatedDateTime:    ' + $priorToCreatedTS)
Write-Output ('-----')
#endregion ShowParameters

#region PrepareMain
# Define different contents used
$contentJson		= 'application/json'							# used for most messages

$sep = $fieldSeparator # Just to make the concatenation more readable.

# Process information from *.ionapi

$ionapi = ( Read-ionapiFile -ionapiFile $ionapiFile )
if ( $ionapi ) {
	Write-Verbose -Message ('Info: Processing ionapi file OK	: ' + $ionapiFile )
} else {
	Write-Verbose -Message ('Info: Processing ionapi file Failed: ' + $ionapiFile )
}

# Define uri based on information in the *.ionapi file
$processPingUri		= $ionapi.iu + '/' + $ionapi.ti + '/IONSERVICES/process/user/ping'
$versionUri			= $ionapi.iu + '/ionapi/metadata/v1/' + $ionapi.ti + '/version'
$imsPingUri			= $ionapi.iu + '/' + $ionapi.ti + '/IONSERVICES/api/ion/messaging/service/ping'

# Request access_token based on authorization code from *.ionapi
Write-Verbose -Message ('Info: Connecting to Tenant		: ' + $ionapi.ti )
Write-Verbose -Message ('Info: Requesting access token')

$OAuth = ( Request-IONAPIToken -ionapiObject $ionapi )
if ( $OAuth ) {
	# the access_token is used in the header for all ION API calls
	$headers	= @{
		'Authorization' = 'Bearer ' + $OAuth.access_token;
		'Accept' = 'application/json'
	}
	Write-Output ('Info: Oauth token received correctly for: ' + $ionapi.ti)
	Write-Verbose -Message ('Info: Token expires in seconds	: ' + $OAuth.expires_in )
	# this value may be needed when your scripts runs longer and the token needs refreshing, to be checked based on timer.
	Write-Verbose -Message ('Info: Token refresh_token		: ' + $Oauth.refresh_token )
	# if no refresh_token, request new access token!
	Write-Verbose -Message ('Info: Token access_token		: ' + $Oauth.access_token )
	Write-Verbose -Message ('Info: Token token type		: ' + $Oauth.token_type )
} else {
	Write-Verbose -Message ('Info: Oauth token not received 		: ' + $ionapiFile )
}

# Testing ION API
Write-Verbose -Message ('-----------------------------------------------------------------------------------------------------------------')
try {
	# This request is a webrequest and responds with a header only
	$response = Invoke-WebRequest -URI $processPingUri -UseBasicParsing -Method Get -ContentType $contentJson -Headers $headers
}
catch{
	Write-Verbose -Message ('Error: Ping fails; ' + $_.Exception.Message )
}
Write-Verbose ('Info: Process User Ping		: ' + $response.StatusDescription )

try {
	$response = Invoke-RestMethod -URI $imsPingUri -Method Get -ContentType $contentJson -Headers $headers
}
catch{
	Write-Verbose -Message ('Error: API Ping fails;' + $_.Exception.Message )
}
Write-Verbose ('Info: Messaging Service Ping		: ' + $response.status )

try {
	$response = Invoke-RestMethod -URI $versionUri -Method Get -ContentType $contentJson -Headers $headers
}
catch{
	Write-Verbose -Message ('Error: ' + $_.Exception.Message )
}
Write-Verbose -Message ('Info: ION API Version			: ' + $response.version )
Write-Verbose -Message ('-----------------------------------------------------------------------------------------------------------------')
#endregion PrepareMain

#region Testing-IDM-ION-API-calls
try {
	$validityIDM = ( Test-IDMValidity -ionapiObject $ionapi -oauthObject $OAuth )
}
catch{
	Write-Verbose -Message ('Error: ' + $_.Exception.Message )
}
if ( $validityIDM ) {
	Write-Output ('Info: IDM validation			: ' + $validityIDM.validated )
} else {
	Write-Verbose -Message ('Info: IDM validation NOT OK' )
}

try {
	$loginIDM = ( Test-IDMLogin -ionapiObject $ionapi -oauthObject $OAuth )
}
catch{
	Write-Verbose -Message ('Error: ' + $_.Exception.Message )
}
if ( $loginIDM ) {
	Write-Output ('Info: IDM connection/login		: OK ')
	Write-Verbose -Message ('Info: IDM login Username		: ' + $loginIDM.properties.property.Where({ $_.name -eq "Username" }).Value )
	Write-Verbose -Message ('Info: IDM login DisplayName		: ' + $loginIDM.properties.property.Where({ $_.name -eq "DisplayName" }).Value )
} else {
	Write-Verbose -Message ('Info: IDM connection login NOT OK' )
}
#endregion Testing-IDM-ION-API-calls

#region Counting-IDM-documents
if ($includeAttributes) { $includeDetails = $true } # Including attributes requires to include details too.
$includeMissingOpened = $false
$cntIDMLogFile = '.\' + $ionapi.ti + '_IDM-Documents-Count.csv'
$missingIDMFile = '.\' + $ionapi.ti + '_IDM-Documents-MissingFiles.csv'

$entityListIDM = ( Read-IDMEntity -ionapiObject $ionapi -oauthObject $OAuth )
if ( $entityListIDM ) {
	Write-Verbose -Message ('---------------------------------------------------------')
	Write-Output ('Info: IDM has # of entities (Document Types) : ' + $entityListIDM.count )
	$logMessage = ('IDM Document Type' + $sep + 'Active' + $sep + 'Archived' + $sep + 'Deleted' + $sep + 'Document Description')
	if ($includeDetails) { $logMessage += $sep + 'Number of files in Active' + $sep + ' Size Active in Bytes' }
	Write-Verbose -Message $logMessage
	Add-Content -Path $cntIDMLogFile -Force -Value $logMessage

	# set timer for access token
	$now = [Math]::Round((Get-Date).ToFileTime()/10000000) # in seconds
	$expirytimeAccessToken = $now + $OAuth.expires_in - 120 # in seconds

	$docIndex = 0
	ForEach ($entityIDM in $entityListIDM) {
		# check timer and refresh or request new token
		$now = [Math]::Round((Get-Date).ToFileTime()/10000000) # in seconds
		if ( $now -GT $expirytimeAccessToken ) {
			$currentOAuth = $OAuth
			$OAuth = ( Request-NewAccessToken -ionapiObject $ionapi -oauthObject $currentOAuth)
			$now = [Math]::Round((Get-Date).ToFileTime()/10000000) # in seconds
			$expirytimeAccessToken = $now + $OAuth.expires_in - 120 # in seconds
			Write-Output ('Info: Access token expired new requested, will expire in ' + $OAuth.expires_in + ' seconds.')
		}
		$nowDateTime = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
		if ((!$specificDocumentType) -or ( $specificDocumentType -eq $entityIDM.name) ) {
			$docIndex ++
			Write-Output ($nowDateTime + ' Start Document Type: ' + $entityIDM.name + ' ' + $docIndex + ' of ' + $entityListIDM.count)
			$entityDetailsIDM = ( Read-IDMEntityDetail -ionapiObject $ionapi -oauthObject $OAuth -entity $entityIDM )
			$totalByteSize	= 0	# set total size of bytes for files of this Document type
			$totalNofFiles	= 0	# set total number of files for this Document type
			if ($includeDetails -and $entityDetailsIDM.ActiveDocuments -gt 0 ) {
				Write-Output ($nowDateTime + ' Collect Details for: ' + $entityIDM.name + ' having ' +  $entityDetailsIDM.ActiveDocuments + ' documents')
				$attrHeader = ''	# Always create it empty to be able to add it unconditionally later.
				if ($includeAttributes) {
					ForEach ($attr in $entityIDM.attrs.attr) {
						$attrHeader += $sep + $attr.Name
					}
					Write-Verbose ('Attributes: ' + $attrHeader)
				}
				# The attributes are reported in same sequence even if attributes are added later or shuffled in sequence, tested in 2025.05 version.

				$detailsIDMFile = '.\' + $ionapi.ti + '_IDM-Documents-details-' + $entityDetailsIDM.name + '.csv'
				$logMessage = ('Pid' + $sep + 'filename' + $sep + 'size' + $sep + 'createdTS' + $sep + 'createdByName' + $sep + 'lastChangedTS' + $sep + 'lastChangedByName' + $attrHeader)
				Write-Verbose -Message $logMessage
				Add-Content -Path $detailsIDMFile -Force -Value $logMessage
				# Set Parameters for /items/search Search for items (by string) these values are used as example to demo and depends on records in your IDM application
				$searchQuery	= $entityDetailsIDM.name	# Query parameter.
				if ( $priorToCreatedTS -ne "" -and $priorToCreatedTS -ne "DEFAULT" )
					{ $searchQuery = $searchQuery + '%5B%40CREATETS%20%3C%20%22' + $priorToCreatedDateTime + '%22%5D%20SORTBY(%40LASTCHANGEDTS%20DESCENDING)' }
				$searchQuery = $searchQuery.Replace(':', '%3A')
				$logMessage = ('Search Query : ' + $searchQuery)
				Write-Verbose -Message $logMessage
				$searchOffset	= 0		# Start index of the search. Use 0 for the first item.
				$searchLimit	= 100		# The maximum number of returned items. Must be between 0 and 1000.
				$searchInclCnt	= 'true'	# If a search count should be included in the result, including a count may result that the operation takes longer time to execute (true = including, false = not including)
				$searchState	= '0' 		# The document state to search for (0 = Active, 1 = Archived and 2 = Deleted).

				do {
					# check timer and refresh or request new token
					$now = [Math]::Round((Get-Date).ToFileTime()/10000000) # in seconds
					if ( $now -GT $expirytimeAccessToken ) {
						$currentOAuth = $OAuth
						$OAuth = ( Request-NewAccessToken -ionapiObject $ionapi -oauthObject $currentOAuth)
						$now = [Math]::Round((Get-Date).ToFileTime()/10000000) # in seconds
						$expirytimeAccessToken = $now + $OAuth.expires_in - 120 # in seconds
						Write-Output ('Info: Access token expired new requested, will expire in ' + $OAuth.expires_in + ' seconds.')
					}
					# search details while the search offset is less than number of active documents found for this Document Type

					Write-Verbose ('Searching for document using search Query : /' + $searchQuery )
					try {
						$itemListIDM = ( Get-IDMItemsSearch -ionapiObject $ionapi -oauthObject $OAuth -query $searchQuery -offset $searchOffset -limit $searchLimit -includeCount $searchInclCnt -state $searchState )
					}
					catch{
						Write-Verbose ('Error: ' + $_.Exception.Message )
					}
					# List information on the result
					if ($itemListIDM) {
						if ([int]$itemListIDM.searchCount -gt 100) {
							# Only show the Progress bar for document types having many documents.
							$searchCompleted = ( $searchOffset / $itemListIDM.searchCount) * 100
							Write-Progress -Activity "Fetching Progress" -Status "$searchCompleted% Complete:" -PercentComplete $searchCompleted
						}
						if ($itemListIDM.item) {
							Write-Verbose ('List of items contains ' + $itemListIDM.item.count + ' items in this selection')
							Write-Verbose ('List of items contains ' + $itemListIDM.searchCount + ' items in total')
						} else {
							Write-Verbose ('List of items contains NO items')
						}
						ForEach ($item in $itemListIDM.item) {
							$attrFields = ''	# Always create it empty to be able to add it unconditionally later.
							if ($includeAttributes) {
								ForEach ($attr in $item.attrs.attr) {
									$attrFields += $sep + '"' + $attr.value + '"'
								}
								Write-Verbose ('Attributes: ' + $attrFields)
							}
							if ( $item.filename ) {
								$totalByteSize += $item.size
								$totalNofFiles += 1
								$itemFilename = '"'+$item.filename+'"'
								$itemSize = $item.size
							} else {
								if ($includeMissingOpened -ne $true) {
									$logMessage = ('IDM Document Type' + $sep + 'Pid' + $sep + 'createdTS' + $sep + 'createdByName' + $sep + 'lastChangedTS' + $sep + 'lastChangedByName')
									Write-Verbose -Message $logMessage
									Add-Content -Path $missingIDMFile -Force -Value $logMessage
									$includeMissingOpened = $true
								}
								$itemFilename = '"MissingFile!"'
								$itemSize = 0
								$logMessage = ($entityDetailsIDM.name + $sep + $item.pid + $sep + $item.createdTS + $sep + '"'+$item.createdByName+'"' + $sep + $item.lastChangedTS + $sep + '"'+$item.lastChangedByName+'"')
								Write-Verbose -Message $logMessage
								Add-Content -Path $missingIDMFile -Force -Value $logMessage
							}
							$logMessage = ($item.pid + $sep + $itemFilename + $sep + $itemSize + $sep + $item.createdTS + $sep + '"'+$item.createdByName+'"' + $sep + $item.lastChangedTS + $sep + '"'+$item.lastChangedByName+'"'+ $attrFields)
							Write-Verbose -Message $logMessage
							Add-Content -Path $detailsIDMFile -Force -Value $logMessage
						}
					} else {
						Write-Verbose ('IDM Get item search returned no documents for the filter used.' )
					}
					$searchOffset += $searchLimit
				}
				while ([int]$searchOffset -lt [int]$itemListIDM.searchCount)
				Write-Progress -Completed
				Write-Verbose -Message ('Document Type: ' + $entityDetailsIDM.name + ' has ' + $totalNofFiles + ' files attached with total size in bytes: '+ $totalByteSize )
			}

			$logMessage = ($entityDetailsIDM.name + $sep + $entityDetailsIDM.ActiveDocuments + $sep + $entityDetailsIDM.ArchivedDocuments + $sep + $entityDetailsIDM.DeletedDocuments + $sep + $entityDetailsIDM.desc )
			if ($includeDetails) { $logMessage += ( $sep + $totalNofFiles + $sep + $totalByteSize ) }

			Write-Verbose -Message $logMessage
			Add-Content -Path $cntIDMLogFile -Force -Value $logMessage
		} # Check on specific Document Type or all
		$nowDateTime = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
		Write-Verbose -Message ($nowDateTime + ' loop to next document ')
	} # loop on $entityListIDM
} else {
	Write-Verbose -Message ('Info: IDM has NO entities (Document Types) configured yet.' )
}
$nowDateTime = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$logMessage = ('Info: completed, run on: ' +  $nowDateTime)
Write-Output $logMessage
$logMessage = ('Info: Summary File Name: ' +  $cntIDMLogFile)
Write-Output $logMessage
$logMessage = ('Info: Details File Name: ' +  $detailsIDMFile)
Write-Output $logMessage
Write-Verbose -Message ('-----------------------------------------------------------------------------------------------------------------')
#endregion Counting-IDM-documents