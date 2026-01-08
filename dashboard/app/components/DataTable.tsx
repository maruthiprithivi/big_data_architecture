'use client'

import { formatNumber } from '@/app/lib/utils'

interface DataTableProps {
  bitcoinBlocks: number
  bitcoinTransactions: number
  solanaBlocks: number
  solanaTransactions: number
  totalRecords: number
}

export default function DataTable({
  bitcoinBlocks,
  bitcoinTransactions,
  solanaBlocks,
  solanaTransactions,
  totalRecords,
}: DataTableProps) {
  const rows = [
    { source: 'Bitcoin', type: 'Blocks', count: bitcoinBlocks },
    { source: 'Bitcoin', type: 'Transactions', count: bitcoinTransactions },
    { source: 'Solana', type: 'Blocks', count: solanaBlocks },
    { source: 'Solana', type: 'Transactions', count: solanaTransactions },
  ]

  return (
    <div className="bg-white rounded-lg shadow border border-gray-200 overflow-hidden">
      <div className="px-6 py-4 border-b border-gray-200">
        <h3 className="text-lg font-bold text-gray-800">Data Breakdown</h3>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Source
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Type
              </th>
              <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Count
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {rows.map((row, index) => (
              <tr key={index} className="hover:bg-gray-50 transition-colors">
                <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                  {row.source}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {row.type}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right font-mono">
                  {formatNumber(row.count)}
                </td>
              </tr>
            ))}
            <tr className="bg-gray-100 font-bold">
              <td
                colSpan={2}
                className="px-6 py-4 text-sm text-gray-900 uppercase"
              >
                Total
              </td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right font-mono">
                {formatNumber(totalRecords)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  )
}
