# Supabase — étapes manuelles

Remplace `2026-07-23-firebase-console-manual-steps.md`, supprimé avec Firebase le 2026-08-02.
Ce qui suit n'est exprimable ni en migration ni en code.

## 1. Authentification — Sign in with Apple

Dashboard → Authentication → Providers → Apple. Le flux natif (`signInWithIdToken`) n'a besoin
que du **bundle ID** de l'app comme *client ID* — pas du Services ID, du Key ID ni de la clé `.p8`
que réclamait le flux web. C'est une étape de moins qu'avec Firebase.

## 2. Secrets des Edge Functions

```sh
supabase secrets set APNS_KEY_ID=… APNS_TEAM_ID=… APNS_BUNDLE_ID=co.antoineteston.NeonCompass
supabase secrets set APNS_PRIVATE_KEY="$(cat AuthKey_XXXX.p8)"
supabase secrets set APNS_HOST=api.sandbox.push.apple.com   # api.push.apple.com en production
supabase secrets set APP_STORE_ENVIRONMENT=sandbox APP_BUNDLE_ID=co.antoineteston.NeonCompass
supabase secrets set APP_STORE_APPLE_ID=…                   # requis en production seulement
```

La clé APNs vient du portail développeur Apple (Keys → APNs). Elle n'est plus téléversée dans une
console tierce : `send-push` signe son propre JWT ES256 avec.

## 3. Secrets du Vault, pour les tâches planifiées

Les tâches `pg_cron` appellent les Edge Functions par HTTP et ont besoin de l'URL et d'une clé.
Écrire ces valeurs dans une migration versionnée serait committer une clé `service_role` :

```sql
select vault.create_secret('https://<ref>.supabase.co', 'project_url');
select vault.create_secret('<service_role>', 'service_role_key');
```

À vérifier ensuite : `select jobname, schedule, active from cron.job;` doit rendre trois lignes —
`refresh-leaderboard`, `rebuild-community-bundles`, `send-push`.

## 4. App Store Connect — URL du webhook

App Store Connect → App → App Information → App Store Server Notifications, URL de production ET
de sandbox :

```
https://<ref>.supabase.co/functions/v1/app-store-notification
```

**Point de contrôle à ne pas sauter au moment de la bascule.** Si l'URL reste celle de Firebase, les
notifications d'abonnement Pro tombent dans le vide — sans erreur visible nulle part.

## 5. Le premier éditeur

Le mode éditeur interne est fermé tant que la table `editors` est vide. Pour l'ouvrir, une ligne :

```sql
insert into public.editors (uid, note) values ('<uid>', 'auteur du projet');
```

Le `uid` se relève au premier armement de l'éditeur, que le bandeau affiche. Cela remplace l'UID
écrit en dur dans `firestore.rules`, qui n'a jamais été renseigné.

## 6. Surveillance de l'egress

Il n'y a pas d'alerte de budget à poser comme chez Google Cloud : sur le plan gratuit, dépasser
l'egress renvoie **402 sur tout le projet** — base et authentification comprises. À surveiller dans
Dashboard → Reports → Egress.

Le seuil qui doit déclencher une décision est le passage au plan Pro : s'il devient nécessaire *à
cause de l'egress statique* et non de la charge applicative, la bonne réponse est de sortir le
contenu vers un hébergeur à egress illimité. `contentBaseURL` dans `app_config` le permet sans mise
à jour de l'app — c'est la porte de sortie prévue par la spec, section D2.
