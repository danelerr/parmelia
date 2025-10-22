import { HermesClient } from '@pythnetwork/hermes-client';
import { HERMES_URL } from './pyth';

let hermesClient: HermesClient | null = null;

export function getHermesClient(): HermesClient {
  if (!hermesClient) {
    hermesClient = new HermesClient(HERMES_URL);
  }
  return hermesClient;
}

export async function getPriceUpdates(feedIds: string[]): Promise<{
  updateData: `0x${string}`[];
  publishTime: number;
}> {
  try {
    const client = getHermesClient();
    const priceUpdates = await client.getLatestPriceUpdates(feedIds);
    
    if (!priceUpdates || !priceUpdates.binary) {
      throw new Error('No price updates available');
    }
    const updateData = priceUpdates.binary.data.map(
      (data) => `0x${data}` as `0x${string}`
    );

    return {
      updateData,
      publishTime: Date.now() / 1000,
    };
  } catch (error) {
    console.error('Error fetching price updates from Hermes:', error);
    throw new Error(
      `Failed to fetch price updates: ${error instanceof Error ? error.message : 'Unknown error'}`
    );
  }
}

export async function getCurrentPrice(feedId: string): Promise<{
  price: number;
  expo: number;
  publishTime: number;
  confidence: number;
}> {
  try {
    const client = getHermesClient();
    const priceUpdates = await client.getLatestPriceUpdates([feedId]);
    
    if (!priceUpdates || !priceUpdates.parsed || priceUpdates.parsed.length === 0) {
      throw new Error('No price data available');
    }

    const priceData = priceUpdates.parsed[0].price;
    
    return {
      price: Number(priceData.price),
      expo: priceData.expo,
      publishTime: priceData.publish_time,
      confidence: Number(priceData.conf),
    };
  } catch (error) {
    console.error('Error fetching current price from Hermes:', error);
    throw new Error(
      `Failed to fetch current price: ${error instanceof Error ? error.message : 'Unknown error'}`
    );
  }
}


export function formatPythPrice(price: number, expo: number): number {
  return price * Math.pow(10, expo);
}

export function formatPriceDisplay(price: number, decimals: number = 2): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  }).format(price);
}
