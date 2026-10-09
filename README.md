# Convert EML to PDF

Converts `.eml` email files into tagged PDFs. Built for the OLLS CORA team who need tagged PDF versions of EML files.

## How to use

- **Double-click** `Convert EML to PDF.exe`, then drag and drop or browse for one or more `.eml` files.
- **Or drag** `.eml` files directly onto the exe.

Each PDF is saved next to its `.eml` file with the same name. If that name is already taken, a number is added, for example `Email (1).pdf`.

## What the PDF contains

- Accessibility tags
- The email's original HTML styling and inline images, so it looks like it did in the email client.
- A header table at the top with Date, From, To, Cc, Subject and Attachments (empty rows are left out). The labels are marked as row headers.
- The email Subject as the PDF Document Title.

## Requirements

- Windows with Microsoft Edge or Google Chrome installed. The browser does the PDF rendering.
- No other software or internet connection is needed.
- Only `.eml` files are supported. Other file types are rejected.

## Files

| Path | Purpose |
|------|---------|
| `Convert EML to PDF.exe` | The tool to give to users |
| `convert-eml-to-pdf.bat` | Source script. Also runs on its own with the same drop/browse behavior |
| `assets/` | Icon used by the exe |
| `build/` | Scripts to rebuild the exe |

## Update the exe

`Convert EML to PDF.exe` contains its own copy of the script from `convert-eml-to-pdf.bat`, so editing the `.bat` does not change the exe. After editing the `.bat`, rebuild the exe:

1. Close the exe if it is running.
2. Run in PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "build\build-exe.ps1"
```

3. Redistribute the new exe. Existing copies are not updated automatically.

To change the icon, replace `assets\convert-eml-to-pdf.ico` and rebuild.

## Notes

- The exe is not code-signed, so security software or IT policy may warn about or block it.
- Users need read access to the folder the exe is in, and write access to the folder where PDFs are saved.