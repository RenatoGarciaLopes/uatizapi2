#!/bin/bash
# Script para remover o ícone adaptativo e evitar corte das bordas do logo

ADAPTIVE_ICON_PATH="android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"

if [ -f "$ADAPTIVE_ICON_PATH" ]; then
    echo "Removendo ícone adaptativo para evitar corte das bordas..."
    rm "$ADAPTIVE_ICON_PATH"
    echo "Ícone adaptativo removido com sucesso!"
else
    echo "Arquivo do ícone adaptativo não encontrado (já foi removido ou não existe)."
fi








