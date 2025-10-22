import { useQuery } from '@tanstack/react-query';
import { usePublicClient, useAccount } from 'wagmi';
import { getCurrentPrice, getPriceUpdates, formatPythPrice } from '../lib/hermesService';
import { getPythContractAddress, PYTH_ABI } from '../lib/pyth';

/**
 * Hook para obtener el precio actual de ETH/USD (solo visualización)
 * 
 * @param feedId - Feed ID de Pyth
 * @param options - Opciones de configuración
 * @returns Query con el precio formateado
 */
export function usePythPrice(
  feedId: string,
  options?: {
    enabled?: boolean;
    refetchInterval?: number;
  }
) {
  return useQuery({
    queryKey: ['pyth-price', feedId],
    queryFn: async () => {
      const priceData = await getCurrentPrice(feedId);
      return {
        ...priceData,
        formattedPrice: formatPythPrice(priceData.price, priceData.expo),
      };
    },
    enabled: options?.enabled ?? true,
    refetchInterval: options?.refetchInterval ?? 10000, // Actualizar cada 10 segundos
    staleTime: 5000, // Considerar datos frescos por 5 segundos
  });
}

/**
 * Hook para obtener price updates para usar en transacciones
 * 
 * @param feedIds - Array de feed IDs
 * @returns Query con updateData y función para calcular fee
 */
export function usePriceUpdates(feedIds: string[]) {
  const publicClient = usePublicClient();
  const { chain } = useAccount();

  return useQuery({
    queryKey: ['pyth-updates', feedIds, chain?.id],
    queryFn: async () => {
      const { updateData } = await getPriceUpdates(feedIds);
      if (!publicClient) {
        throw new Error('Public client not available');
      }

      const pythAddress = getPythContractAddress(chain);
      
      const fee = await publicClient.readContract({
        address: pythAddress,
        abi: PYTH_ABI,
        functionName: 'getUpdateFee',
        args: [updateData],
      });

      return {
        updateData,
        fee,
        timestamp: Date.now(),
      };
    },
    enabled: !!publicClient && !!chain && feedIds.length > 0,
    staleTime: 3000, // Los updates son válidos por 3 segundos
    gcTime: 1000, // Limpiar cache rápido
  });
}

/**
 * Hook para verificar si los price updates son recientes
 * 
 * @param maxAge - Edad máxima permitida en segundos
 */
export function usePriceUpdateAge(timestamp: number | undefined, maxAge: number = 60) {
  if (!timestamp) return { isValid: false, age: null };
  
  const age = (Date.now() - timestamp) / 1000; // edad en segundos
  const isValid = age <= maxAge;
  
  return { isValid, age };
}
