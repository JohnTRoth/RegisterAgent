<#
    .SYNOPSIS
    Register server in Azure Pipelines environment.
    .DESCRIPTION
    Downloads and installs agent on the server and then registers the server in an Azure Pipelines environment.
    This script is based on the registration script that you can copy from the Azure DevOps portal when manually adding a Virtual machine resource to an environment.
    .PARAMETER OrganizationUrl
    URL of the organization. For example: https://myaccount.visualstudio.com or http://onprem:8080/tfs.
    .PARAMETER TeamProject
    Name of the team project. For example myProject.
    .PARAMETER Environment
    Name of the deployment pool. For example: Customers.
    .PARAMETER Token
    Personal Access Token. The token needs the scope 'Environment (Read & manage)' in Azure DevOps.
    .PARAMETER Tags
    Optional comma separated list of tags to add to the server. For example: "web, sql".
    .EXAMPLE
    PS> .\register-server-in-environment.ps1 -OrganizationUrl https://myaccount.visualstudio.com -TeamProject myProject -Environment myEnvironment -Token myToken
    .EXAMPLE
    PS> .\register-server-in-environment.ps1 -OrganizationUrl https://myaccount.visualstudio.com -TeamProject myProject -Environment myEnvironment -Token myToken -Tags "web, sql"
#>
param (
    [Parameter(Mandatory)][string]$OrganizationUrl,
    [Parameter(Mandatory)][string]$TeamProject,
    [Parameter(Mandatory)][string]$Environment,
    [Parameter(Mandatory)][string]$Token,
    [Parameter(Mandatory)][string]$uid,
    [Parameter(Mandatory)][string]$pass,
    [string]$Tags
)


$ErrorActionPreference="Stop";
If(-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent() ).IsInRole( [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    throw "Run command in an administrator PowerShell prompt"
};

If($PSVersionTable.PSVersion -lt (New-Object System.Version("3.0")))
{
    throw "The minimum version of Windows PowerShell that is required by the script (3.0) does not match the currently running version of Windows PowerShell."
};


$agentName = $env:COMPUTERNAME;

"Creating agent dir"
If(-NOT (Test-Path $env:SystemDrive\'agent'))
{
    mkdir $env:SystemDrive\'agent'
    cd $env:SystemDrive\'agent';
    $agentZip="$PWD\agent.zip";
    "Donloading $agentZip"

    # Configure the web client used to download the zip file with the agent
    $DefaultProxy=[System.Net.WebRequest]::DefaultWebProxy;
    $securityProtocol=@();
    $securityProtocol+=[Net.ServicePointManager]::SecurityProtocol;
    $securityProtocol+=[Net.SecurityProtocolType]::Tls12;
    [Net.ServicePointManager]::SecurityProtocol=$securityProtocol;
    $WebClient=New-Object Net.WebClient; 
    $WebClient.Headers.Add("user-agent", "azure pipeline");


    ## Retrieve list with releases for the Azure Pipelines agent
    $releasesUrl = "https://api.github.com/repos/Microsoft/azure-pipelines-agent/releases"
    if($DefaultProxy -and (-not $DefaultProxy.IsBypassed($releasesUrl)))
    {
        $WebClient.Proxy= New-Object Net.WebProxy($DefaultProxy.GetProxy($releasesUrl).OriginalString, $True);
    };
    $releases = $WebClient.DownloadString($releasesUrl) | ConvertFrom-Json


    ## Select the newest agent release
    $latestAgentRelease = $releases | Sort-Object -Property published_at -Descending | Select-Object -First 1
    $assetsUrl = $latestAgentRelease.assets[0].browser_download_url

    ## Get the agent download url from the agent release assets
    if($DefaultProxy -and (-not $DefaultProxy.IsBypassed($assetsUrl)))
    {
        $WebClient.Proxy= New-Object Net.WebProxy($DefaultProxy.GetProxy($assetsUrl).OriginalString, $True);
    };
    $assets = $WebClient.DownloadString($assetsUrl) | ConvertFrom-Json
    $Uri = $assets | Where-Object { $_.platform -eq "win-x64"} | Select-Object -First 1 | Select-Object -ExpandProperty downloadUrl

    "Downloading from $Uri"

    # Download the zip file with the agent
    if($DefaultProxy -and (-not $DefaultProxy.IsBypassed($Uri)))
    {
        $WebClient.Proxy= New-Object Net.WebProxy($DefaultProxy.GetProxy($Uri).OriginalString, $True);
    };
    Write-Host "Download agent zip file from $Uri";
    $WebClient.DownloadFile($Uri, $agentZip);

    "Downloaded - Extracting $agentZip"
    # Extract the zip file
    Add-Type -AssemblyName System.IO.Compression.FileSystem;
    [System.IO.Compression.ZipFile]::ExtractToDirectory( $agentZip, "$PWD");

    "Removing zip"
    # Remove the zip file
    Remove-Item $agentZip;

} else {
    cd $env:SystemDrive\'agent';
    "Removing previous agent"
    # Remove previous (template) installation
    "Calling .\config.cmd remove --unattended --auth PAT --token $Token"
    .\config.cmd remove --unattended --auth PAT --token $Token
}


"Registering"
# Register the agent in the environment
"Calling .\config.cmd --unattended  --agent $agentName --runasservice --work '_work' --url $OrganizationUrl --auth PAT --token $Token --pool $Environment --replace --projectname $TeamProject --windowsLogonAccount $uid --windowsLogonPassword $pass"
.\config.cmd --unattended  --agent $agentName --runasservice --work '_work' --url $OrganizationUrl --auth PAT --token $Token --pool $Environment --replace --projectname $TeamProject --windowsLogonAccount "$uid" --windowsLogonPassword "$pass"


# Raise an exception if the registration of the agent failed
if ($LastExitCode -ne 0)
{
    throw "Error during registration. See '$PWD\_diag' for more information.";
}
"Completed!"
