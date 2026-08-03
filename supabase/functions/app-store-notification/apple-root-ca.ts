// Certificat racine « Apple Root CA - G3 », celui qui signe la chaîne actuelle
// des App Store Server Notifications. Téléchargé depuis
// https://www.apple.com/certificateauthority/ — la bibliothèque d'Apple ne le
// fournit pas, son propre README demande de le passer soi-même.
//
// **Embarqué en base64, et pas lu depuis un fichier voisin.** Le déploiement des
// Edge Functions n'empaquette que ce qui est ATTEINT PAR UN IMPORT : un
// `Deno.readFile('./certs/…')` passe la compilation, passe `deno check`, se
// déploie sans un mot — et échoue en production par un 500 au premier appel
// d'Apple. Vérifié le 2026-08-03 : le `.cer` n'était pas dans l'archive
// déployée, seuls les deux fichiers TypeScript l'étaient.
//
// Un certificat racine est public et stable sur des années ; l'inliner ne coûte
// que 800 caractères et supprime toute dépendance à un empaquetage implicite.
export const APPLE_ROOT_CA_G3_BASE64 =
  'MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9v' +
  'dCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UE' +
  'CgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2' +
  'WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmlj' +
  'YXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqG' +
  'SM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxE' +
  'tX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNC' +
  'MEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0P' +
  'AQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3m' +
  'eoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkL' +
  'F1vLUagM6BgD56KyKA==';
