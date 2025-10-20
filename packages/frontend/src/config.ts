import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { type Address, type Chain } from "viem";
import { sepolia, localhost } from "viem/chains";

export function paymentTokenAddress(chain: Chain | undefined): Address {
  switch (chain) {
    case undefined:
    case sepolia:
    case localhost:
      // PYUSD Sepolia
      return "0xCaC524BcA292aaade2DF8A05cC58F0a65B1B3bB9";
    default:
      throw new Error(
        `Payment token address not configured for chain ${chain}`
      );
  }
}

export function helloPyusdAddress(chain: Chain | undefined): Address {
  switch (chain) {
    case undefined:
    case sepolia:
    case localhost:
      // use your own HelloPYUSD address, or this one!
      return "0xc32ef01341487792201F6EFD908aB52CDC7b0775";
    default:
      throw new Error(`HelloPyusd address not configured for chain ${chain}`);
  }
}


export const wagmiConfig = getDefaultConfig({
  appName: 'Parmelia',
  projectId: '41ba725fce5fa6ba53da8cb6192b41ae',
  chains: [sepolia, localhost],
  ssr: false,
});
