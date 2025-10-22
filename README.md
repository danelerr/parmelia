# Parmelia

Parmelia es una plataforma de gestión de treasury DeFi que utiliza smart contracts para automatizar estrategias de inversión basadas en oráculos de precios.

## 🎨 Identidad Visual

Parmelia utiliza una paleta de colores inspirada en la naturaleza:
- **Cyan** `#A7D4DE` - Color principal
- **Pink** `#DEA6BC` - Color secundario  
- **Yellow** `#DED9A6` - Color de acento
- **White** `#FFFFFF` - Modo claro
- **Black** `#1E1E1E` - Modo oscuro

**Fuente**: Shippori Antique (Google Fonts)

Para más detalles sobre el sistema de diseño, consulta [`packages/frontend/DESIGN.md`](./packages/frontend/DESIGN.md).

## 📁 Estructura del Proyecto

```
parmelia/
├── packages/
│   ├── contracts/    # Smart contracts con Hardhat 3 y Solidity
│   ├── frontend/     # Aplicación React + Vite + RainbowKit
│   └── indexer/      # Indexador (en desarrollo)
├── package.json
└── pnpm-workspace.yaml
```

## 🚀 Requisitos Previos

- **Node.js** (v18 o superior)
- **pnpm** v10.18.3 (se instalará automáticamente con corepack)

## 📦 Instalación

1. **Clonar el repositorio**
   ```bash
   git clone <repository-url>
   cd parmelia
   ```

2. **Instalar dependencias**
   ```bash
   pnpm install
   ```

   Esto instalará todas las dependencias de todos los paquetes en el workspace.
