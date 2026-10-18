#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
printf 'Configuration de la notarisation DS-720D\n\n'
printf 'Le mot de passe spécifique à l’application sera demandé ici par Apple.\n'
printf 'Il sera enregistré dans le Trousseau ; ne le colle pas dans une conversation.\n\n'
DS_TEAM_ID=$(/usr/bin/codesign -d --verbose=2 '/Applications/DS-720D Scanner.app' 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p' || true)
if [[ ! "$DS_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    read -r -p 'Identifiant de ton équipe Apple Developer : ' DS_TEAM_ID
fi
[[ "$DS_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { printf 'Identifiant d’équipe invalide.\n' >&2; exit 64; }
read -r -p 'Adresse de ton compte Apple Developer : ' DS_APPLE_ID
[[ -n "$DS_APPLE_ID" ]] || exit 64
DS_PROFILE="ds720d-notary-$DS_TEAM_ID"
printf '\nNom du profil : %s\n' "$DS_PROFILE"
/usr/bin/xcrun notarytool store-credentials "$DS_PROFILE" --apple-id "$DS_APPLE_ID" --team-id "$DS_TEAM_ID"
printf '\nConfiguration terminée. Nom du profil : %s\n' "$DS_PROFILE"
read -r -p 'Appuie sur Entrée pour fermer cette fenêtre.' DS_DONE
