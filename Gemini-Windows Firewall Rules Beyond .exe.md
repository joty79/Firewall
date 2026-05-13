# Windows Firewall Rules Beyond .exe

**Exported:** 5/14/2026 1:32:01  
**Link:** [https://gemini.google.com/app/225d6d7e0c36ae21](https://gemini.google.com/app/225d6d7e0c36ae21)

## Prompt:
which files i should block or generally put firewall rules except from .exe in windows

## Response:
Στο οικοσύστημα των Windows, ο περιορισμός μόνο των αρχείων **_.exe_** είναι το πρώτο βήμα, αλλά για έναν 🔸**_Senior Systems Engineer_**, η πραγματική ασφάλεια βρίσκεται στον έλεγχο των **_interpreters_** και των **_LOLBins (Living Off the Land Binaries)_**.

* * *

### 🔵 **Script Interpreters & Shells**

Πολλά **_malware_** δεν χρησιμοποιούν δικά τους αρχεία **_.exe_**, αλλά εκμεταλλεύονται τα υπάρχοντα εργαλεία του συστήματος για να εκτελέσουν κώδικα στη μνήμη.

*   🔸**_powershell.exe_** & **_pwsh.exe_**: Αν ένα script δεν χρειάζεται πρόσβαση στο internet, μπλόκαρε την εξερχόμενη κίνηση (**_Outbound Rules_**).
*   🔸**_cscript.exe_** & **_wscript.exe_**: Χρησιμοποιούνται για την εκτέλεση **_VBScript_** και **_JScript_**.
*   🔸**_mshta.exe_**: Εκτελεί **_HTML Applications (.hta)_** και είναι κλασικό εργαλείο για **_fileless attacks_**.

* * *

### 🔵 **Επικίνδυνες Επεκτάσεις Αρχείων**

Εκτός από τα εκτελέσιμα, υπάρχουν τύποι αρχείων που το σύστημα αντιμετωπίζει ως κώδικα. Αυτά θα έπρεπε να παρακολουθούνται ή να μπλοκάρονται από το **_Firewall_** ή το **_AppLocker_**:

*   🔸**_.com_** & **_.pif_**: Παλαιού τύπου εκτελέσιμα που παραμένουν λειτουργικά.
*   🔸**_.scr_**: Αρχεία **_Screen Saver_** που στην πραγματικότητα είναι **_executables_**.
*   🔸**_.cpl_**: Αρχεία **_Control Panel_**, συχνά σημεία για **_DLL hijacking_**.
*   🔸**_.msi_** & **_.msp_**: Πακέτα εγκατάστασης που μπορούν να κατεβάσουν επιπλέον **_payloads_**.

* * *

### 🔵 **LOLBins (Living Off the Land Binaries)**

Αυτά είναι νόμιμα αρχεία των Windows που μπορούν να χρησιμοποιηθούν για τη λήψη (download) κακόβουλου λογισμικού παρακάμπτοντας το **_Firewall_**.

*   🔸**_certutil.exe_**: Χρησιμοποιείται για τη διαχείριση πιστοποιητικών, αλλά μπορεί να κατεβάσει αρχεία από το internet με το flag `-urlcache`.
*   🔸**_bitsadmin.exe_**: Το **_Background Intelligent Transfer Service_** μπορεί να χρησιμοποιηθεί για μεταφορά αρχείων στο παρασκήνιο.
*   🔸**_regsvr32.exe_**: Μπορεί να εκτελέσει απομακρυσμένα **_scripts_** μέσω **_COM objects_**.

* * *

### 🔵 **Υλοποίηση μέσω PowerShell 7**

Εφόσον χρησιμοποιείς **_PS7_**, μπορείς να δημιουργήσεις γρήγορα κανόνες για την απαγόρευση εξόδου σε ύποπτα binaries.

```
# Παράδειγμα μπλοκαρίσματος του certutil για Outbound κίνηση
New-NetFirewallRule -DisplayName "Block CertUtil Internet Access" `
    -Direction Outbound `
    -Program "C:\Windows\System32\certutil.exe" `
    -Action Block
```

* * *

### 🔵 **Στρατηγικές Συμβουλές (Best Practices)**

*   ⚠️ **Προσοχή:** Μην μπλοκάρεις το **_svchost.exe_** καθολικά, καθώς θα διακόψεις βασικές υπηρεσίες του συστήματος (DNS, Updates).
*   💡 **Tip:** Χρησιμοποίησε το **_Windows Defender Application Control (WDAC)_** ή το **_AppLocker_** για να περιορίσεις την εκτέλεση αυτών των αρχείων, αντί να βασίζεσαι μόνο στο **_Firewall_**.
*   ✅ **Success:** Ο συνδυασμός **_Firewall Rules_** για **_outbound traffic_** σε **_LOLBins_** και η χρήση **_Execution Policy_** στο **_PowerShell_** προσφέρουν ένα ισχυρό επίπεδο θωράκισης.

* * *

Ποιες συγκεκριμένες υπηρεσίες ή **_environment_** θέλεις να θωρακίσεις περισσότερο (π.χ. ένα **_Hyper-V VM_** ή ένα **_debloated_** σύστημα πελάτη);



---
Powered by [Gemini Exporter](https://www.ai-chat-exporter.com)