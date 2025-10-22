import "@rainbow-me/rainbowkit/styles.css";

import { RainbowKitProvider, lightTheme, darkTheme } from "@rainbow-me/rainbowkit";
import { WagmiProvider } from "wagmi";
import { wagmiConfig } from "./config.ts";
import { Toaster } from "react-hot-toast";

import { QueryClientProvider, QueryClient } from "@tanstack/react-query";
import HelloPyusd from "./components/HelloPyusd";

const queryClient = new QueryClient();

const parmeliaLightTheme = lightTheme({
  accentColor: '#A7D4DE',
  accentColorForeground: '#1E1E1E',
  borderRadius: 'medium',
  fontStack: 'system',
  overlayBlur: 'small',
});

const parmeliaDarkTheme = darkTheme({
  accentColor: '#A7D4DE',
  accentColorForeground: '#1E1E1E',
  borderRadius: 'medium',
  fontStack: 'system',
  overlayBlur: 'small',
});

// Customización adicional de los temas
const customLightTheme = {
  ...parmeliaLightTheme,
  colors: {
    ...parmeliaLightTheme.colors,
    accentColor: '#A7D4DE',
    accentColorForeground: '#1E1E1E',
    actionButtonBorder: '#DEA6BC',
    actionButtonBorderMobile: '#DEA6BC',
    actionButtonSecondaryBackground: '#DED9A6',
    closeButton: '#1E1E1E',
    closeButtonBackground: '#A7D4DE',
    connectButtonBackground: '#FFFFFF',
    connectButtonBackgroundError: '#DEA6BC',
    connectButtonInnerBackground: '#A7D4DE',
    connectButtonText: '#1E1E1E',
    connectButtonTextError: '#1E1E1E',
    connectionIndicator: '#A7D4DE',
    error: '#DEA6BC',
    generalBorder: '#DED9A6',
    generalBorderDim: 'rgba(222, 217, 166, 0.3)',
    menuItemBackground: 'rgba(167, 212, 222, 0.1)',
    modalBackdrop: 'rgba(30, 30, 30, 0.3)',
    modalBackground: '#FFFFFF',
    modalBorder: '#A7D4DE',
    modalText: '#1E1E1E',
    modalTextDim: 'rgba(30, 30, 30, 0.6)',
    modalTextSecondary: 'rgba(30, 30, 30, 0.7)',
    profileAction: 'rgba(167, 212, 222, 0.1)',
    profileActionHover: 'rgba(167, 212, 222, 0.2)',
    profileForeground: '#FFFFFF',
    selectedOptionBorder: '#DED9A6',
    standby: '#DEA6BC',
  },
};

const customDarkTheme = {
  ...parmeliaDarkTheme,
  colors: {
    ...parmeliaDarkTheme.colors,
    accentColor: '#A7D4DE',
    accentColorForeground: '#1E1E1E',
    actionButtonBorder: '#DEA6BC',
    actionButtonBorderMobile: '#DEA6BC',
    actionButtonSecondaryBackground: '#DED9A6',
    closeButton: '#FFFFFF',
    closeButtonBackground: '#A7D4DE',
    connectButtonBackground: '#1E1E1E',
    connectButtonBackgroundError: '#DEA6BC',
    connectButtonInnerBackground: 'rgba(167, 212, 222, 0.2)',
    connectButtonText: '#FFFFFF',
    connectButtonTextError: '#FFFFFF',
    connectionIndicator: '#A7D4DE',
    error: '#DEA6BC',
    generalBorder: '#DED9A6',
    generalBorderDim: 'rgba(222, 217, 166, 0.2)',
    menuItemBackground: 'rgba(167, 212, 222, 0.05)',
    modalBackdrop: 'rgba(0, 0, 0, 0.5)',
    modalBackground: '#1E1E1E',
    modalBorder: '#A7D4DE',
    modalText: '#FFFFFF',
    modalTextDim: 'rgba(255, 255, 255, 0.6)',
    modalTextSecondary: 'rgba(255, 255, 255, 0.7)',
    profileAction: 'rgba(167, 212, 222, 0.05)',
    profileActionHover: 'rgba(167, 212, 222, 0.1)',
    profileForeground: 'rgba(30, 30, 30, 0.8)',
    selectedOptionBorder: '#DED9A6',
    standby: '#DEA6BC',
  },
};

function App() {
  return (
    <>
      <WagmiProvider config={wagmiConfig}>
        <QueryClientProvider client={queryClient}>
          <RainbowKitProvider
            theme={{
              lightMode: customLightTheme,
              darkMode: customDarkTheme,
            }}
          >
            <HelloPyusd />
            <Toaster
              toastOptions={{
                success: {
                  icon: "✨",
                  style: {
                    background: '#A7D4DE',
                    color: '#1E1E1E',
                  },
                },
                error: {
                  icon: "⚠️",
                  style: {
                    background: '#DEA6BC',
                    color: '#1E1E1E',
                  },
                },
                loading: {
                  icon: "⏳",
                  style: {
                    background: '#DED9A6',
                    color: '#1E1E1E',
                  },
                },
                position: "bottom-right",
                duration: 5000,
                style: {
                  borderRadius: '8px',
                  fontFamily: '"Shippori Antique", sans-serif',
                },
              }}
            />
          </RainbowKitProvider>
        </QueryClientProvider>
      </WagmiProvider>
    </>
  );
}

export default App;
