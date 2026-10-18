DS-720D Scanner — version expérimentale

Ouvre « Installer DS-720D.pkg ». Une autorisation administrateur est demandée
à l’installation. Le paquet ajoute l’application, le module Transfert d’images
et un service USB démarré à la demande. Les scans ne demandent plus de mot de
passe administrateur. macOS peut demander une fois l’accès aux supports amovibles
pour communiquer avec l’interface USB du scanner. Branche exactement un Brother DS-720D et insère une
feuille. L’application produit deux PNG à 300 dpi ; ferme puis rouvre Transfert
d’images pour y retrouver aussi le scanner.

Tu peux choisir le dossier de destination et désactiver le nettoyage pour
conserver les couleurs et les ombrages acquis. « Conserver la capture » garde
aussi les données nécessaires au retraitement, qui occupent davantage de place.
Le menu Fichier permet de retraiter une capture sans faire tourner le scanner.

Les composants installés sont :
  /Applications/DS-720D Scanner.app
  /Library/Image Capture/Devices/DS720DICA.app
  /Library/PrivilegedHelperTools/info.korben.ds720d.usb
  /Library/LaunchDaemons/info.korben.ds720d.usb.plist

Le service accepte uniquement les clients du projet signés avec le même compte
Developer ID. Aucune commande système, chemin de fichier ou commande USB
arbitraire n’est accepté. Il prépare uniquement la connexion USB. L’acquisition
et le traitement des images restent dans ta session.

Le moteur et le module Transfert d’images ont produit un scan recto verso réel
à 300 dpi sur Apple Silicon, avec macOS 27.0.1. Les erreurs de papier, la
déconnexion et l’annulation demandent encore des tests matériels. Utilise des
feuilles de test ordinaires.

Code source et mises à jour : https://github.com/Korben00/ds720d-macos
Licence MIT. Aucune bibliothèque ni aucun pilote constructeur n’est embarqué.

English: open the installer package and authorize installation once. Then use
Image Capture or DS-720D Scanner without administrator prompts for each scan.
This independent experimental MIT driver supports 300 dpi RGB duplex scans.
