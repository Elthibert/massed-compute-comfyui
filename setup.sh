#!/bin/bash

# ====================================================================
# Script d'auto-installation ComfyUI pour Massed Compute
# À coller dans le script de démarrage de Massed Compute
# ====================================================================

# Ce script fait tout automatiquement :
# 1. Clone et installe ComfyUI
# 2. Crée des raccourcis desktop cliquables
# 3. Lance automatiquement ComfyUI si souhaité

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ====================================================================
# CONFIGURATION
# ====================================================================

COMFYUI_DIR="$HOME/ComfyUI"
DESKTOP_DIR="$HOME/Desktop"
SCRIPTS_DIR="$HOME/comfyui-scripts"

# ====================================================================
# PARTIE 1: INSTALLATION SYSTÈME
# ====================================================================

log_info "🚀 Début de l'installation automatique ComfyUI pour Massed Compute"

# Créer le dossier Desktop s'il n'existe pas
mkdir -p "$DESKTOP_DIR"
mkdir -p "$SCRIPTS_DIR"

# Installation des dépendances système
log_info "📦 Installation des dépendances système..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    python3-pip python3-venv python3-dev \
    build-essential libgl1-mesa-glx libglib2.0-0 \
    libsm6 libxext6 libxrender1 libgomp1 \
    wget curl git ffmpeg \
    libcudnn8 libcudnn8-dev \
    xterm zenity 2>/dev/null || true

# ====================================================================
# PARTIE 2: INSTALLATION COMFYUI
# ====================================================================

log_info "🔧 Création des scripts d'installation..."

# Créer le script d'installation principal
cat > "$SCRIPTS_DIR/install_comfyui.sh" << 'INSTALL_SCRIPT'
#!/bin/bash

COMFYUI_DIR="$HOME/ComfyUI"
VENV_DIR="$COMFYUI_DIR/venv"
CUSTOM_NODES_DIR="$COMFYUI_DIR/custom_nodes"

echo "🔧 Installation de ComfyUI..."

# Clone ou update ComfyUI
if [ -d "$COMFYUI_DIR" ]; then
    echo "Mise à jour de ComfyUI..."
    cd "$COMFYUI_DIR" && git pull
else
    echo "Clonage de ComfyUI..."
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR"
fi

cd "$COMFYUI_DIR"

# Environnement virtuel Python
echo "Création de l'environnement Python..."
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

# Mise à jour pip
pip install --upgrade pip wheel setuptools

# PyTorch avec CUDA
echo "Installation de PyTorch avec support CUDA..."
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

# Requirements ComfyUI
echo "Installation des dépendances ComfyUI..."
pip install -r requirements.txt

# Packages supplémentaires utiles
echo "Installation des packages supplémentaires..."
pip install opencv-python transformers accelerate safetensors \
    omegaconf einops torchsde kornia spandrel soundfile

# xformers pour optimisation mémoire
echo "Installation de xformers..."
pip install xformers --index-url https://download.pytorch.org/whl/cu121

# Custom nodes essentiels
echo "Installation des custom nodes essentiels..."
mkdir -p "$CUSTOM_NODES_DIR"

# ComfyUI Manager
[ ! -d "$CUSTOM_NODES_DIR/ComfyUI-Manager" ] && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git "$CUSTOM_NODES_DIR/ComfyUI-Manager"

# Impact Pack
[ ! -d "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack" ] && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack"

# Efficiency Nodes
[ ! -d "$CUSTOM_NODES_DIR/efficiency-nodes-comfyui" ] && \
    git clone https://github.com/jags111/efficiency-nodes-comfyui.git "$CUSTOM_NODES_DIR/efficiency-nodes-comfyui"

# WAS Node Suite
[ ! -d "$CUSTOM_NODES_DIR/was-node-suite-comfyui" ] && \
    git clone https://github.com/WASasquatch/was-node-suite-comfyui.git "$CUSTOM_NODES_DIR/was-node-suite-comfyui"

# Créer structure dossiers
echo "Création de la structure des dossiers..."
mkdir -p "$COMFYUI_DIR"/{models/{checkpoints,vae,loras,embeddings,controlnet,clip,upscale_models},input,output,temp}

echo "✅ Installation ComfyUI terminée!"
INSTALL_SCRIPT

chmod +x "$SCRIPTS_DIR/install_comfyui.sh"

# ====================================================================
# PARTIE 3: CRÉATION DES LANCEURS
# ====================================================================

log_info "🎨 Création des raccourcis desktop..."

# Script de lancement ComfyUI
cat > "$SCRIPTS_DIR/start_comfyui.sh" << 'START_SCRIPT'
#!/bin/bash
cd "$HOME/ComfyUI"
source venv/bin/activate

# Détection automatique du port disponible
PORT=8188
while lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null ; do
    PORT=$((PORT+1))
done

echo "🚀 Lancement de ComfyUI sur le port $PORT"
echo "📍 Accès local: http://localhost:$PORT"
echo "📍 Accès distant: http://$(hostname -I | awk '{print $1}'):$PORT"
echo ""
echo "🔥 Massed Compute - ComfyUI est prêt!"
echo ""
echo "Pour arrêter: Ctrl+C"

python main.py --listen 0.0.0.0 --port $PORT --cuda-device 0 --use-pytorch-cross-attention
START_SCRIPT

chmod +x "$SCRIPTS_DIR/start_comfyui.sh"

# Script de téléchargement de modèles depuis fichier config
cat > "$SCRIPTS_DIR/download_models.sh" << 'DOWNLOAD_SCRIPT'
#!/bin/bash

MODELS_DIR="$HOME/ComfyUI/models"
CONFIG_FILE="$HOME/comfyui-scripts/models_config.txt"
CONFIG_URL="https://raw.githubusercontent.com/Elthibert/massed-compute-comfyui/main/models_config.txt"

# Fonction de téléchargement avec barre de progression
download_model() {
    local TYPE=$1
    local URL=$2
    local NAME=$3
    local DESC=$4
    
    # Déterminer le dossier de destination selon le type
    case $TYPE in
        CHECKPOINT) DEST_DIR="$MODELS_DIR/checkpoints" ;;
        VAE) DEST_DIR="$MODELS_DIR/vae" ;;
        UPSCALER) DEST_DIR="$MODELS_DIR/upscale_models" ;;
        CONTROLNET) DEST_DIR="$MODELS_DIR/controlnet" ;;
        LORA) DEST_DIR="$MODELS_DIR/loras" ;;
        EMBEDDING) DEST_DIR="$MODELS_DIR/embeddings" ;;
        UNET) DEST_DIR="$MODELS_DIR/unet" ;;
        CLIP) DEST_DIR="$MODELS_DIR/clip" ;;
        *) DEST_DIR="$MODELS_DIR/other" ;;
    esac
    
    mkdir -p "$DEST_DIR"
    
    echo "📥 Téléchargement: $NAME"
    echo "   Type: $TYPE"
    echo "   Description: $DESC"
    echo "   Destination: $DEST_DIR"
    
    # Nom du fichier depuis l'URL
    FILENAME=$(basename "$URL" | sed 's/?.*//g')
    
    # Télécharger avec wget
    wget --progress=bar:force -c "$URL" -O "$DEST_DIR/$FILENAME" 2>&1
    
    if [ $? -eq 0 ]; then
        echo "✅ $NAME téléchargé avec succès!"
    else
        echo "❌ Erreur lors du téléchargement de $NAME"
    fi
    echo "---"
}

# Menu principal
show_menu() {
    echo "===================================="
    echo "    TÉLÉCHARGEMENT DES MODÈLES"
    echo "===================================="
    echo ""
    echo "1) Télécharger depuis le fichier de config"
    echo "2) Éditer le fichier de config"
    echo "3) Télécharger le fichier de config depuis GitHub"
    echo "4) Télécharger TOUS les modèles du config"
    echo "5) Mode interactif (choisir les modèles)"
    echo "6) Quitter"
    echo ""
}

# Mode interactif avec zenity
interactive_mode() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "❌ Fichier de config non trouvé. Téléchargement..."
        wget -q "$CONFIG_URL" -O "$CONFIG_FILE" 2>/dev/null || {
            echo "Création d'un fichier de config par défaut..."
            create_default_config
        }
    fi
    
    # Lire les modèles disponibles
    MODELS_LIST=""
    while IFS='|' read -r TYPE URL NAME DESC; do
        # Ignorer les commentaires et lignes vides
        [[ "$TYPE" =~ ^#.*$ ]] || [ -z "$TYPE" ] && continue
        MODELS_LIST="$MODELS_LIST FALSE \"$NAME\" \"$DESC\" \"$TYPE\""
    done < "$CONFIG_FILE"
    
    # Afficher le menu de sélection
    eval "zenity --list --title=\"Sélection des modèles\" \
        --text=\"Cochez les modèles à télécharger:\" \
        --checklist --column=\"Choix\" --column=\"Modèle\" --column=\"Description\" --column=\"Type\" \
        --width=700 --height=500 \
        $MODELS_LIST" | while IFS='|' read -r SELECTED; do
        
        # Télécharger les modèles sélectionnés
        while IFS='|' read -r TYPE URL NAME DESC; do
            [[ "$TYPE" =~ ^#.*$ ]] || [ -z "$TYPE" ] && continue
            if [[ "$SELECTED" == *"$NAME"* ]]; then
                download_model "$TYPE" "$URL" "$NAME" "$DESC"
            fi
        done < "$CONFIG_FILE"
    done
}

# Créer un fichier de config par défaut VIDE
create_default_config() {
    cat > "$CONFIG_FILE" << 'EOF'
# Fichier de configuration des modèles pour ComfyUI
# Format: TYPE|URL|NOM|DESCRIPTION
# 
# Décommentez les lignes pour activer le téléchargement automatique
# Ajoutez vos propres modèles en suivant le même format
#
# Exemples:
# CHECKPOINT|https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors|SD 1.5|Stable Diffusion 1.5
# VAE|https://huggingface.co/stabilityai/sd-vae-ft-mse-original/resolve/main/vae-ft-mse-840000-ema-pruned.safetensors|VAE Standard|VAE pour SD 1.5
# LORA|https://example.com/my_lora.safetensors|Mon LoRA|Description
EOF
}

# Télécharger automatiquement les modèles non-commentés
auto_download() {
    echo "📥 Téléchargement automatique des modèles activés..."
    
    while IFS='|' read -r TYPE URL NAME DESC; do
        # Ignorer les lignes commentées et vides
        [[ "$TYPE" =~ ^#.*$ ]] || [ -z "$TYPE" ] && continue
        
        download_model "$TYPE" "$URL" "$NAME" "$DESC"
    done < "$CONFIG_FILE"
    
    echo "✅ Téléchargement automatique terminé!"
}

# Programme principal
if command -v zenity &> /dev/null; then
    # Si zenity est disponible, mode interactif
    interactive_mode
else
    # Sinon, mode CLI
    while true; do
        show_menu
        read -p "Choix: " choice
        
        case $choice in
            1)
                if [ ! -f "$CONFIG_FILE" ]; then
                    echo "Téléchargement du fichier de config..."
                    wget -q "$CONFIG_URL" -O "$CONFIG_FILE" || create_default_config
                fi
                auto_download
                ;;
            2)
                nano "$CONFIG_FILE" || vi "$CONFIG_FILE"
                ;;
            3)
                wget "$CONFIG_URL" -O "$CONFIG_FILE"
                echo "✅ Config téléchargée depuis GitHub"
                ;;
            4)
                # Télécharger TOUS les modèles (même commentés)
                sed 's/^#//' "$CONFIG_FILE" | while IFS='|' read -r TYPE URL NAME DESC; do
                    [ -z "$TYPE" ] && continue
                    download_model "$TYPE" "$URL" "$NAME" "$DESC"
                done
                ;;
            5)
                echo "Mode interactif nécessite zenity. Installation..."
                sudo apt-get install -y zenity
                interactive_mode
                ;;
            6)
                exit 0
                ;;
            *)
                echo "Option invalide"
                ;;
        esac
        
        read -p "Appuyez sur Entrée pour continuer..."
    done
fi
DOWNLOAD_SCRIPT

chmod +x "$SCRIPTS_DIR/download_models.sh"

# ====================================================================
# PARTIE 4: CRÉATION DES RACCOURCIS DESKTOP
# ====================================================================

# Raccourci pour installer ComfyUI (première utilisation)
cat > "$DESKTOP_DIR/1_Install_ComfyUI.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=🔧 Installer ComfyUI
Comment=Première installation de ComfyUI (Massed Compute)
Exec=xterm -geometry 120x40 -title "Installation ComfyUI - Massed Compute" -e "bash $SCRIPTS_DIR/install_comfyui.sh; echo 'Appuyez sur Entrée pour fermer...'; read"
Icon=system-software-install
Terminal=false
Categories=Application;
EOF

# Raccourci pour lancer ComfyUI
cat > "$DESKTOP_DIR/2_Launch_ComfyUI.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=🚀 Lancer ComfyUI
Comment=Démarrer ComfyUI sur Massed Compute
Exec=xterm -geometry 120x30 -title "ComfyUI - Massed Compute" -hold -e "bash $SCRIPTS_DIR/start_comfyui.sh"
Icon=applications-graphics
Terminal=false
Categories=Application;
EOF

# Raccourci pour télécharger des modèles
cat > "$DESKTOP_DIR/3_Download_Models.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=📥 Télécharger Modèles
Comment=Télécharger des modèles IA
Exec=bash $SCRIPTS_DIR/download_models.sh
Icon=download
Terminal=false
Categories=Application;
EOF

# Raccourci pour ouvrir le dossier ComfyUI
cat > "$DESKTOP_DIR/4_ComfyUI_Folder.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=📁 Dossier ComfyUI
Comment=Ouvrir le dossier ComfyUI
Exec=xdg-open $COMFYUI_DIR
Icon=folder
Terminal=false
Categories=Application;
EOF

# Rendre tous les raccourcis exécutables
chmod +x "$DESKTOP_DIR"/*.desktop

# Permettre l'exécution des fichiers desktop (pour certains environnements)
gio set "$DESKTOP_DIR"/*.desktop metadata::trusted true 2>/dev/null || true

# ====================================================================
# PARTIE 5: SCRIPT AUTO-RUN (OPTIONNEL)
# ====================================================================

# Créer un script qui installe ET lance automatiquement
cat > "$DESKTOP_DIR/AUTO_START_ALL.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=⚡ AUTO TOUT FAIRE
Comment=Installe et lance ComfyUI automatiquement (Massed Compute)
Exec=bash -c "if [ ! -d '$COMFYUI_DIR/venv' ]; then xterm -geometry 120x40 -title 'Installation - Massed Compute' -e 'bash $SCRIPTS_DIR/install_comfyui.sh'; fi; xterm -geometry 120x30 -title 'ComfyUI - Massed Compute' -hold -e 'bash $SCRIPTS_DIR/start_comfyui.sh'"
Icon=starred
Terminal=false
Categories=Application;
StartupNotify=true
EOF

chmod +x "$DESKTOP_DIR/AUTO_START_ALL.desktop"

# Script pour importer des workflows depuis une URL
cat > "$SCRIPTS_DIR/import_workflow.sh" << 'IMPORT_SCRIPT'
#!/bin/bash

WORKFLOW_URL=$(zenity --entry --title="Importer un Workflow" \
    --text="Entrez l'URL du workflow (GitHub, Huggingface, etc.):" \
    --width=500)

if [ ! -z "$WORKFLOW_URL" ]; then
    WORKFLOW_DIR="$HOME/ComfyUI/workflows"
    mkdir -p "$WORKFLOW_DIR"
    
    FILENAME=$(basename "$WORKFLOW_URL")
    wget "$WORKFLOW_URL" -O "$WORKFLOW_DIR/$FILENAME"
    
    if [ $? -eq 0 ]; then
        zenity --info --text="Workflow importé avec succès!\n\nFichier: $FILENAME\nDossier: $WORKFLOW_DIR" --width=300
    else
        zenity --error --text="Erreur lors du téléchargement du workflow" --width=300
    fi
fi
IMPORT_SCRIPT

chmod +x "$SCRIPTS_DIR/import_workflow.sh"

# Raccourci pour importer des workflows
cat > "$DESKTOP_DIR/5_Import_Workflow.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=📤 Importer Workflow
Comment=Importer un workflow depuis une URL
Exec=bash $SCRIPTS_DIR/import_workflow.sh
Icon=document-import
Terminal=false
Categories=Application;
EOF

chmod +x "$DESKTOP_DIR/5_Import_Workflow.desktop"

# ====================================================================
# PARTIE 6: TÉLÉCHARGEMENT AUTO DES MODÈLES DE BASE
# ====================================================================

# Créer le fichier de config des modèles s'il n'existe pas
if [ ! -f "$SCRIPTS_DIR/models_config.txt" ]; then
    log_info "📝 Création du fichier de configuration des modèles..."
    
    # Essayer de télécharger depuis GitHub
    wget -q "https://raw.githubusercontent.com/Elthibert/massed-compute-comfyui/main/models_config.txt" \
         -O "$SCRIPTS_DIR/models_config.txt" 2>/dev/null
    
    # Si pas de téléchargement ou échec, créer config minimale
    if [ ! -f "$SCRIPTS_DIR/models_config.txt" ]; then
        cat > "$SCRIPTS_DIR/models_config.txt" << 'CONFIG'
# Config minimale - Modèles essentiels activés par défaut
VAE|https://huggingface.co/stabilityai/sd-vae-ft-mse-original/resolve/main/vae-ft-mse-840000-ema-pruned.safetensors|VAE Standard|VAE pour SD 1.5
UPSCALER|https://huggingface.co/datasets/jiboli/upscalers/resolve/main/4x-UltraSharp.pth|4x-UltraSharp|Upscaler HQ
CONFIG
    fi
fi

# Option: Télécharger automatiquement les modèles non-commentés au démarrage
# Décommentez la ligne suivante pour activer le téléchargement auto
# bash "$SCRIPTS_DIR/download_models.sh" auto &

# ====================================================================
# PARTIE 7: MESSAGE FINAL
# ====================================================================

# Créer un fichier README sur le desktop
cat > "$DESKTOP_DIR/README_COMFYUI.txt" << 'README'
===========================================
    COMFYUI SUR MASSED COMPUTE - GUIDE
===========================================

🎯 UTILISATION DES RACCOURCIS:
--------------------------------
1. Double-cliquez sur "1_Install_ComfyUI" (première fois seulement)
2. Double-cliquez sur "2_Launch_ComfyUI" pour démarrer
3. Ouvrez votre navigateur sur http://localhost:8188

OU

Double-cliquez sur "⚡ AUTO TOUT FAIRE" qui fait tout automatiquement!

📥 MODÈLES:
-----------
- Utilisez "3_Download_Models" pour télécharger des modèles de base
- Ou placez vos propres modèles dans ComfyUI/models/
- Utilisez "5_Import_Workflow" pour importer des workflows

📁 STRUCTURE DES DOSSIERS:
--------------------------
ComfyUI/
├── models/
│   ├── checkpoints/  (modèles principaux)
│   ├── loras/        (LoRAs)
│   ├── vae/          (VAE)
│   └── embeddings/   (embeddings)
├── input/            (images d'entrée)
├── output/           (images générées)
├── workflows/        (vos workflows)
└── custom_nodes/     (extensions)

💡 TIPS MASSED COMPUTE:
-----------------------
- ComfyUI Manager est pré-installé
- Les logs apparaissent dans le terminal
- Ctrl+C pour arrêter ComfyUI
- Le GPU est automatiquement détecté et utilisé

🔥 OPTIMISATIONS:
-----------------
- xformers activé pour économiser la VRAM
- PyTorch cross-attention activé
- Support CUDA 12.1

===========================================
README

log_info "✅ Installation terminée pour Massed Compute!"
log_info "📍 Raccourcis créés sur le Desktop"
log_info "🚀 Double-cliquez sur les icônes pour commencer!"

# Message de notification (si disponible)
which notify-send >/dev/null 2>&1 && notify-send "Massed Compute" "ComfyUI est prêt! Raccourcis disponibles sur le Desktop" -i dialog-information

# Optionnel: Lancer automatiquement l'installation
# bash "$SCRIPTS_DIR/install_comfyui.sh"