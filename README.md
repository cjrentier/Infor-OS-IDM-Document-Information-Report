# Infor OS - IDM Document Information Report
## Name
Read-IDMDocumentInformation.ps1
## Synopsis

Collect information about Documents in Infor Document Management.
Default is to count Documents per Document Type for each state: Active, Archived and Deleted. This takes few minutes typically.
Output is a csv file having all document types and their numbers named: '\<Tenant\>_IDM-Documents-Count.csv'

Use the includeDetails switch to include information about the Active documents having no file attached and count the total size of all Active documents. This takes considerably more time!
The information about missing files is stored in a csv file named: '\<Tenant\>_IDM-Documents-MissingFiles.csv'

Use the includeAttributes switch to include all Single-value attributes per Document on top of the includeDetails.
The detailed information is stored in a csv file per Document Type named: '\<Tenant\>_IDM-Documents-details-\<Document Name\>.csv'

The MDS_ID column is present in case the option Use Unique ID is active for that Document Type.

The fieldSeparator can be defined: ';', ',', '|', default = ';'

The priorToCreatedTS can be used to read only documents based on the TimeStamp they were created initially.

## Syntax
    .\Read-IDMDocumentInformation.ps1 
        [-ionapiFile] <String> 
        [-includeDetails] 
        [-includeAttributes] 
        [[-specificDocumentType] <String>]
        [[-fieldSeparator] <String>]
        [-priorToCreatedTS YYYY-MM-DD]
        [<CommonParameters>]

## Description
Preparation by user. Required Security Roles: IDM-User & IDM-SuperUser (to count Deleted Documents!)
1.  Create Authorized App in ION API of type Backend Service, link it to a user with sufficient Security Roles to call APIs, store this in a safe place as it contains sensitive data
2.  Download ION API file *.ionapi file
3.  Set your ExecutionPolicy for example: set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser
4.  Start this script with the corresponding parameters

## Example
Start the PowerShell script selecting the required methode.

To count the documents by Document Type:

    .\Read-IDMDocumentInformation.ps1 -ionapiFile '.\YourTenant.ionapi'

To count the documents by Document Type including the Active documents having no file attached and the total size of all Active documents.

    .\Read-IDMDocumentInformation.ps1 -ionapiFile '.\YourTenant.ionapi' -includeDetails

To include all attributes per document, this includes the details too.

    .\Read-IDMDocumentInformation.ps1 -ionapiFile '.\YourTenant.ionapi' -includeAttributes

To collect data for one Document Type only, specify the Name in IDM, instead of the Display name.

    .\Read-IDMDocumentInformation.ps1 -ionapiFile '.\YourTenant.ionapi' -specificDocumentType 'Item_Images'

To define a specific field separator to be used for the CSV, ';', ',', '|', default = ';'

    .\Read-IDMDocumentInformation.ps1 -ionapiFile '.\YourTenant.ionapi' -fieldSeparator ','

To select only documents created before specific date: yyyy-mm-dd. This will use XQuery like: /OPL_Templates[@CREATETS < "2025-06-16T23:59:59.999Z"] SORTBY(@LASTCHANGEDTS DESCENDING)

    .\Read-IDMDocumentInformation.ps1 -ionapiFile '.\YourTenant.ionapi' -priorToCreatedTS 2025-06-16


## Output Examples
### Output Example '\<Tenant\>_IDM-Documents-Count.csv'

| IDM Document Type | Active | Archived | Deleted | Document Description | Number of files in Active | Size Active in Bytes |
| ----------------- | ------ | -------- | ------- | -------------------- | ------------------------- | -------------------- |
| Chat_Attachment   |      3 |        2 |       2 | Chat Attachment | 3 | 256 |
| MDS_GenericDocument | 1640 | 0 | 197 | Document | 1640 | 606514367 |
| MDS_File | 1 | 0 | 0 | File | 1 | 606036 |
| INVOICE | 40123 | 0 | 0 | Invoice | 40121 | 53124342 |
| PurchaseInvoice | 7 | 0 | 0 | Purchase Invoice | 7 | 1485657 |
| SalesOrder | 2132 | 0 | 1 | Sales Order | 2130 | 436313246 |
| Forecast | 1686 | 0 | 6 | Forecast | 1686 | 31579443 |

Above shows that SalesOrder has two Documents not having a file attached. Below report shows which are missing.

### Output Example '\<Tenant\>_IDM-Documents-MissingFiles.csv'

| IDM Document Type | Pid | createdTS | createdByName | lastChangedTS | lastChangedByName |
| ----------------- | --- | --------- | ------------- | ------------- | ----------------- |
| SalesOrder | SalesOrder-105-1-LATEST | 02/13/2014 15:49:23 | "Peter Kings" | 02/15/2014 15:49:23 | "King Peters" |
| SalesOrder | SalesOrder-106-1-LATEST | 02/13/2014 15:52:26 | "King Peters" | 02/16/2014 15:52:26 | "Peter Kings" |

### Output Example '\<Tenant\>_IDM-Documents-details-\<Document Name\>.csv'
Below for one Document Type having few attributes, Document Type = SalesOrder.
| Pid | filename | size | createdTS | createdByName | lastChangedTS | lastChangedByName | MDS_EntityType | MDS_AccountingEntity | MDS_Location | SalesOrderNumber | MDS_ID | ShipToBP |
| --- | -------- | ---- | --------- | ------------- | ------------- | ----------------- | -------------- | -------------------- | - | - | - | - |
| SalesOrder-31-1-LATEST | "ASN321298.docx" | 142051 | 06/27/2013 11:10:41 | "George Halen" | 06/27/2013 11:10:41 | "George Halen" | "InforSalesOrder" | "infor.ln.5010" | "" | "SQ20000078" | "43bd55a2-317c" | "" |
| SalesOrder-32-1-LATEST | "Sales Order SQ20000078.pdf" | 2941514 | 07/04/2013 07:42:22 | "George Halen" | 07/04/2013 07:42:22 | "George Halen" | "InforSalesOrder" | "infor.ln.5010" | "" | "SQ20000078" | "7642efac-a1a9" | "" |
| SalesOrder-33-1-LATEST | "Sales Order SQ20000088.pdf" | 2919553 | 07/06/2013 09:36:24 | "George Michael" | 07/06/2013 09:36:24 | "George Michael" | "InforSalesOrder" | "infor.ln.5010" | "" | "SQ20000088" | "bf26b230-b648480ef6f13aeb" | "" |
| SalesOrder-34-1-LATEST | "Sales Order SQ20000089.pdf" | 2251343 | 07/06/2013 11:16:24 | "Karoline Scalar" | 07/06/2013 11:16:24 | "Karoline Scalar" | "InforSalesOrder" | "infor.ln.5010" | "" | "SQ20000089" | "e85523af-5a81" | "" |


## Support
Contact me for support.

## Roadmap
Currently no idea to extend this script on reporting IDM Document Information.
