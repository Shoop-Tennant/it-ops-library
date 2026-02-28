function Remove-PiiFromString {
    <#
    .SYNOPSIS
        Redacts common PII patterns from a text string.

    .DESCRIPTION
        Replaces emails, SSNs, phone numbers, IPv4 addresses, and UNC/internal
        hostnames with safe placeholders. Designed for sanitizing ticket updates,
        logs, or KB content before external sharing.

    .PARAMETER InputText
        The string to sanitize.

    .EXAMPLE
        Remove-PiiFromString -InputText "Contact john.doe@tennantco.com or call 612-555-1234"
        # Returns: "Contact [EMAIL] or call [PHONE]"

    .EXAMPLE
        Get-Content .\export.txt | Remove-PiiFromString
        # Pipeline support for bulk sanitization.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$InputText
    )

    process {
        $redacted = $InputText

        # Email addresses
        $redacted = $redacted -replace '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}', '[EMAIL]'

        # SSN (XXX-XX-XXXX)
        $redacted = $redacted -replace '\b\d{3}-\d{2}-\d{4}\b', '[SSN]'

        # US phone numbers (various formats)
        $redacted = $redacted -replace '\b(\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b', '[PHONE]'

        # IPv4 addresses
        $redacted = $redacted -replace '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b', '[IP_ADDRESS]'

        # UNC paths (\\server\share)
        $redacted = $redacted -replace '\\\\[A-Za-z0-9._\-]+\\[A-Za-z0-9$._\-\\]+', '[UNC_PATH]'

        # Windows device/hostname patterns (e.g., YOURPC-1234, WS-NA-0042)
        $redacted = $redacted -replace '\b[A-Z]{2,6}-[A-Z]{0,4}-?\d{3,6}\b', '[DEVICE]'

        $redacted
    }
}
