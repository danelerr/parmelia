import { type Chain } from 'viem';
import { sepolia, localhost } from 'viem/chains';

export const HERMES_URL = 'https://hermes.pyth.network';

/**
 * Feed ID para ETH/USD en Pyth Network
 * Este es el identificador único para el par de precio ETH/USD
 * Documentación: https://pyth.network/developers/price-feed-ids
 */
export const ETH_USD_FEED_ID = '0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace';

const PYTH_CONTRACT_ADDRESSES: Record<number, `0x${string}`> = {
  [sepolia.id]: '0xDd24F84d36BF92C65F92307595335bdFab5Bbd21',  
  [localhost.id]: '0xDd24F84d36BF92C65F92307595335bdFab5Bbd21',
};

export function getPythContractAddress(chain: Chain | undefined): `0x${string}` {
  const chainId = chain?.id || sepolia.id;
  const address = PYTH_CONTRACT_ADDRESSES[chainId];
  
  if (!address) {
    throw new Error(`Pyth contract address not configured for chain ${chainId}`);
  }
  
  return address;
}

export const PYTH_ABI = [
  {
    name: 'getUpdateFee',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'updateData', type: 'bytes[]' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'updatePriceFeeds',
    type: 'function',
    stateMutability: 'payable',
    inputs: [{ name: 'updateData', type: 'bytes[]' }],
    outputs: [],
  },
  {
    name: 'getPriceNoOlderThan',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'id', type: 'bytes32' },
      { name: 'age', type: 'uint256' },
    ],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'price', type: 'int64' },
          { name: 'conf', type: 'uint64' },
          { name: 'expo', type: 'int32' },
          { name: 'publishTime', type: 'uint256' },
        ],
      },
    ],
  },
] as const;

export const PRICE_FEEDS = {
  ETH_USD: {
    id: ETH_USD_FEED_ID,
    name: 'ETH/USD',
    description: 'Ethereum to US Dollar',
  },
} as const;
