'use client'

import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts'

interface BlockchainChartProps {
  bitcoinBlocks: number
  bitcoinTransactions: number
  solanaBlocks: number
  solanaTransactions: number
}

export default function BlockchainChart({
  bitcoinBlocks,
  bitcoinTransactions,
  solanaBlocks,
  solanaTransactions,
}: BlockchainChartProps) {
  const data = [
    {
      name: 'Bitcoin',
      Blocks: bitcoinBlocks,
      Transactions: bitcoinTransactions,
    },
    {
      name: 'Solana',
      Blocks: solanaBlocks,
      Transactions: solanaTransactions,
    },
  ]

  return (
    <div className="bg-white rounded-lg shadow p-6 border border-gray-200">
      <h3 className="text-lg font-bold text-gray-800 mb-4">
        Records by Blockchain Source
      </h3>
      <ResponsiveContainer width="100%" height={300}>
        <BarChart data={data} margin={{ top: 5, right: 30, left: 20, bottom: 5 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis dataKey="name" />
          <YAxis />
          <Tooltip
            formatter={(value: number | undefined) =>
              value !== undefined ? new Intl.NumberFormat('en-US').format(value) : '0'
            }
          />
          <Legend />
          <Bar dataKey="Blocks" fill="#F7931A" name="Blocks" />
          <Bar dataKey="Transactions" fill="#9945FF" name="Transactions" />
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}
