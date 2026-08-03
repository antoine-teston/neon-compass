# Supabase — étapes manuelles

Remplace `2026-07-23-firebase-console-manual-steps.md`, supprimé avec Firebase le 2026-08-02.
Ce qui suit n'est exprimable ni en migration ni en code.

## 1. Authentification — Sign in with Apple

Dashboard → Authentication → Providers → Apple. Le flux natif (`signInWithIdToken`) n'a besoin
que du **bundle ID** de l'app comme *client ID* — pas du Services ID, du Key ID ni de la clé `.p8`
que réclamait le flux web. C'est une étape de moins qu'avec Firebase.

## 1 bis. Connexion par e-mail — la confirmation doit être désactivée

Constaté le 2026-08-03 : `mailer_autoconfirm` valait `false` et `rate_limit_email_sent` vaut **2 par
heure**. L'inscription par e-mail était donc cassée pour tout le monde après deux comptes — GoTrue
répond `email rate limit exceeded`, sans que rien n'indique que la cause est un quota d'envoi.

Deux réponses possibles, et il faut en choisir une :

- **Désactiver la confirmation** (ce qui est fait). L'inscription ouvre une session immédiatement.
  Le coût : quelqu'un peut s'inscrire avec l'adresse d'un autre. Ici la conséquence est faible — le
  compte ne sert qu'à ancrer la synchronisation de progression, aucun message n'est jamais envoyé à
  cette adresse, et rien d'autre n'y est rattaché. La victime perdrait seulement la possibilité
  d'utiliser cette adresse plus tard.
- **Configurer un SMTP dédié** (Authentication → Emails → SMTP Settings) et remettre la confirmation.
  C'est la bonne réponse le jour où l'adresse sert à autre chose qu'à un identifiant.

## 1 ter. URL de redirection OAuth

Le flux Google revient dans l'app par un schéma d'URL personnalisé. Il doit être déclaré aux **trois**
endroits, et une seule omission laisse le navigateur ouvert sur une page blanche, sans erreur :

| Où | Valeur |
|---|---|
| `NeonCompass/Support/Info-Ads.plist` | `CFBundleURLSchemes` = `co.antoineteston.neoncompass` |
| `SupabaseAuthProvider.oauthRedirectURL` | `co.antoineteston.neoncompass://auth-callback` |
| Dashboard → Authentication → URL Configuration | même URL dans *Redirect URLs* |

Un test (`EmailAuthModelTests.theOAuthRedirectMatchesTheDeclaredURLScheme`) fige l'accord entre les
deux premiers ; le troisième ne peut être vérifié que sur le projet.

## 1 quater. Provider Google

Il exige des identifiants OAuth créés côté Google, que rien dans ce dépôt ne peut produire :

1. Google Cloud Console → APIs & Services → Credentials → Create OAuth client ID → **Web application**
   (et non « iOS » : c'est Supabase qui reçoit la redirection, pas l'app).
2. *Authorized redirect URI* : `https://quyynxabhjpzsqbblqrj.supabase.co/auth/v1/callback`
3. Dashboard Supabase → Authentication → Providers → Google : activer, coller le *Client ID* et le
   *Client Secret*.

**Rappel de conformité** : proposer Google oblige à proposer aussi Sign in with Apple (règle App
Store 4.8). C'est le cas, et le bouton Apple reste en tête de l'écran.

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
