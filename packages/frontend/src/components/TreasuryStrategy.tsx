/**
 * Componente para ejecutar la estrategia del ParmeliaTreasury
 * Muestra el precio actual de ETH/USD y permite ejecutar swaps
 */

import { useState } from 'react';
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import toast from 'react-hot-toast';

import { usePythPrice, usePriceUpdates } from '../hooks/usePyth';
import { ETH_USD_FEED_ID } from '../lib/pyth';
import { formatPriceDisplay } from '../lib/hermesService';

// TODO: Importar el ABI de tu contrato ParmeliaTreasury
// import { TREASURY_ABI } from '../abi/ParmeliaTreasury';

// TODO: Configurar tu dirección del Treasury
// const TREASURY_ADDRESS = '0x...' as `0x${string}`;

export default function TreasuryStrategy() {
  const { isConnected } = useAccount();
  const [isExecuting, setIsExecuting] = useState(false);

  // 1. Obtener precio actual para mostrar en UI
  const { 
    data: priceData, 
    isLoading: priceLoading,
    error: priceError 
  } = usePythPrice(ETH_USD_FEED_ID);

  // 2. Obtener price updates para la transacción
  const { 
    data: updateData, 
    isLoading: updatesLoading,
    refetch: refetchUpdates 
  } = usePriceUpdates([ETH_USD_FEED_ID]);

  // 3. Hook para escribir en el contrato (preparado para cuando tengas el ABI)
  const { 
    // writeContract, // Descomentar cuando tengas el ABI
    data: hash,
    isPending: isWritePending,
    error: writeError 
  } = useWriteContract();

  // 4. Esperar confirmación de transacción
  const { 
    isLoading: isConfirming, 
    isSuccess: isConfirmed 
  } = useWaitForTransactionReceipt({
    hash,
  });

  // Handler para ejecutar la estrategia
  const handleExecuteStrategy = async () => {
    if (!isConnected) {
      toast.error('Please connect your wallet first');
      return;
    }

    if (!updateData) {
      toast.error('Price updates not available');
      return;
    }

    setIsExecuting(true);
    
    try {
      // Refrescar los updates antes de ejecutar
      const { data: freshUpdates } = await refetchUpdates();
      
      if (!freshUpdates) {
        throw new Error('Failed to fetch fresh price updates');
      }

      // TODO: Descomentar cuando tengas el ABI
      /*
      writeContract({
        address: TREASURY_ADDRESS,
        abi: TREASURY_ABI,
        functionName: 'executeStrategy',
        args: [freshUpdates.updateData],
        value: freshUpdates.fee, // msg.value para pagar el fee de Pyth
      });
      */

      toast.loading('Executing strategy...', { id: 'execute-strategy' });
      
      console.log('Strategy execution params:', {
        updateData: freshUpdates.updateData,
        fee: freshUpdates.fee.toString(),
        timestamp: freshUpdates.timestamp,
      });

      // Simulación temporal
      toast.success('Strategy would be executed!', { id: 'execute-strategy' });
      
    } catch (error) {
      console.error('Error executing strategy:', error);
      toast.error(
        `Failed to execute strategy: ${error instanceof Error ? error.message : 'Unknown error'}`,
        { id: 'execute-strategy' }
      );
    } finally {
      setIsExecuting(false);
    }
  };

  // Efectos para toast notifications
  if (isConfirmed) {
    toast.success('Strategy executed successfully! 🎉', { id: 'execute-strategy' });
  }

  if (writeError) {
    toast.error(`Transaction failed: ${writeError.message}`, { id: 'execute-strategy' });
  }

  return (
    <div className="card max-w-2xl mx-auto">
      <div className="space-y-6">
        {/* Header */}
        <div className="text-center">
          <h2 className="text-2xl font-bold text-parmelia-cyan">Treasury Strategy</h2>
          <p className="text-sm text-gray-500 mt-2">
            Execute automated ETH purchases based on Pyth oracle prices
          </p>
        </div>

        {/* Price Display */}
        <div className="bg-parmelia-black bg-opacity-5 dark:bg-parmelia-white dark:bg-opacity-5 rounded-lg p-6">
          <div className="text-center">
            <p className="text-sm font-medium text-gray-500 mb-2">Current ETH/USD Price</p>
            {priceLoading ? (
              <div className="text-3xl font-bold">Loading...</div>
            ) : priceError ? (
              <div className="text-red-500">Error loading price</div>
            ) : priceData ? (
              <>
                <div className="text-4xl font-bold text-parmelia-cyan">
                  {formatPriceDisplay(priceData.formattedPrice)}
                </div>
                <p className="text-xs text-gray-400 mt-2">
                  Updated: {new Date(priceData.publishTime * 1000).toLocaleTimeString()}
                </p>
              </>
            ) : (
              <div className="text-gray-400">No price data</div>
            )}
          </div>
        </div>

        {/* Strategy Info */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
          <div className="bg-parmelia-pink bg-opacity-10 rounded-lg p-4">
            <p className="font-medium text-parmelia-pink">Update Fee</p>
            <p className="text-lg font-bold mt-1">
              {updateData ? `${Number(updateData.fee) / 1e18} ETH` : '...'}
            </p>
          </div>
          <div className="bg-parmelia-yellow bg-opacity-10 rounded-lg p-4">
            <p className="font-medium text-parmelia-yellow">Status</p>
            <p className="text-lg font-bold mt-1">
              {isConnected ? 'Ready' : 'Not Connected'}
            </p>
          </div>
        </div>

        {/* Execute Button */}
        <button
          onClick={handleExecuteStrategy}
          disabled={
            !isConnected || 
            isExecuting || 
            isWritePending || 
            isConfirming || 
            updatesLoading ||
            !updateData
          }
          className="w-full bg-parmelia-cyan hover:bg-parmelia-pink text-parmelia-black font-bold py-4 px-6 rounded-lg transition-all disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {!isConnected
            ? 'Connect Wallet to Execute'
            : isExecuting || isWritePending || isConfirming
            ? 'Executing Strategy...'
            : 'Execute Strategy'}
        </button>

        {/* Transaction Hash */}
        {hash && (
          <div className="text-center text-sm">
            <p className="text-gray-500">Transaction Hash:</p>
            <code className="text-xs bg-gray-100 dark:bg-gray-800 px-2 py-1 rounded">
              {hash.slice(0, 10)}...{hash.slice(-8)}
            </code>
          </div>
        )}

        {/* Debug Info (solo desarrollo) */}
        {process.env.NODE_ENV === 'development' && updateData && (
          <details className="text-xs text-gray-500">
            <summary className="cursor-pointer hover:text-parmelia-cyan">
              Debug Info (Development Only)
            </summary>
            <pre className="mt-2 bg-gray-100 dark:bg-gray-800 p-2 rounded overflow-x-auto">
              {JSON.stringify({
                priceData,
                updateDataLength: updateData.updateData.length,
                fee: updateData.fee.toString(),
                timestamp: updateData.timestamp,
              }, null, 2)}
            </pre>
          </details>
        )}
      </div>
    </div>
  );
}
