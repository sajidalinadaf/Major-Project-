import React, { useState } from 'react';
import { Package, QrCode, AlertTriangle, ArrowUpDown, Plus, Search, ShieldCheck } from 'lucide-react';

export default function App() {
  const [items, setItems] = useState([
    { id: 'SKU-1001', name: 'Industrial Drill Bits', category: 'Hardware', qty: 45, threshold: 10, bay: 'A-12', status: 'In Stock' },
    { id: 'SKU-1002', name: 'Hydraulic Motor 2HP', category: 'Machinery', qty: 4, threshold: 8, bay: 'B-04', status: 'Low Stock' },
    { id: 'SKU-1003', name: 'Packaging Straps (50m)', category: 'Packaging', qty: 120, threshold: 20, bay: 'C-01', status: 'In Stock' },
    { id: 'SKU-1004', name: 'Safety Goggles Pro', category: 'PPE', qty: 2, threshold: 15, bay: 'D-08', status: 'Critical' },
  ]);

  const [scanSku, setScanSku] = useState('');
  const [scanQty, setScanQty] = useState(1);
  const [scanType, setScanType] = useState('IN');

  const handleSimulateScan = (e) => {
    e.preventDefault();
    if (!scanSku) return;

    setItems((prev) =>
      prev.map((item) => {
        if (item.id.toLowerCase() === scanSku.trim().toLowerCase()) {
          const delta = scanType === 'IN' ? Number(scanQty) : -Number(scanQty);
          const newQty = Math.max(0, item.qty + delta);
          let newStatus = 'In Stock';
          if (newQty === 0) newStatus = 'Out of Stock';
          else if (newQty <= item.threshold) newStatus = 'Low Stock';

          return { ...item, qty: newQty, status: newStatus };
        }
        return item;
      })
    );
    setScanSku('');
    setScanQty(1);
  };

  return (
    <div className="min-h-screen bg-slate-900 text-slate-100 p-6">
      {/* Header */}
      <header className="max-w-7xl mx-auto flex flex-col md:flex-row justify-between items-start md:items-center pb-6 border-b border-slate-800 gap-4">
        <div>
          <div className="flex items-center gap-2">
            <Package className="w-8 h-8 text-blue-500" />
            <h1 className="text-2xl font-bold tracking-tight">Smart Warehouse Management</h1>
          </div>
          <p className="text-sm text-slate-400 mt-1">Cloud-Connected Automated Scanning & Inventory Tracking</p>
        </div>
        <div className="flex items-center gap-3">
          <span className="flex items-center gap-1.5 text-xs bg-emerald-950 text-emerald-400 border border-emerald-800 px-3 py-1.5 rounded-full font-medium">
            <ShieldCheck className="w-4 h-4" /> AWS Serverless Connected
          </span>
        </div>
      </header>

      {/* Main Grid */}
      <main className="max-w-7xl mx-auto grid grid-cols-1 lg:grid-cols-3 gap-6 mt-6">
        
        {/* Left Column: Fast Inbound/Outbound Scanner Mock */}
        <div className="bg-slate-800/60 border border-slate-700 rounded-xl p-5 h-fit">
          <div className="flex items-center gap-2 mb-4">
            <QrCode className="w-5 h-5 text-blue-400" />
            <h2 className="text-lg font-semibold">Barcode Scanning Unit</h2>
          </div>

          <form onSubmit={handleSimulateScan} className="space-y-4">
            <div>
              <label className="text-xs font-medium text-slate-400 block mb-1">Select Action</label>
              <div className="grid grid-cols-2 gap-2">
                <button
                  type="button"
                  onClick={() => setScanType('IN')}
                  className={`py-2 text-sm font-medium rounded-lg border transition ${
                    scanType === 'IN' ? 'bg-blue-600 border-blue-500 text-white' : 'bg-slate-900 border-slate-700 text-slate-400'
                  }`}
                >
                  Inbound (Stock IN)
                </button>
                <button
                  type="button"
                  onClick={() => setScanType('OUT')}
                  className={`py-2 text-sm font-medium rounded-lg border transition ${
                    scanType === 'OUT' ? 'bg-amber-600 border-amber-500 text-white' : 'bg-slate-900 border-slate-700 text-slate-400'
                  }`}
                >
                  Outbound (Stock OUT)
                </button>
              </div>
            </div>

            <div>
              <label className="text-xs font-medium text-slate-400 block mb-1">Scanned SKU Number</label>
              <input
                type="text"
                placeholder="e.g. SKU-1001"
                value={scanSku}
                onChange={(e) => setScanSku(e.target.value)}
                className="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-slate-100 focus:outline-none focus:border-blue-500"
                required
              />
            </div>

            <div>
              <label className="text-xs font-medium text-slate-400 block mb-1">Quantity</label>
              <input
                type="number"
                min="1"
                value={scanQty}
                onChange={(e) => setScanQty(e.target.value)}
                className="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-slate-100 focus:outline-none focus:border-blue-500"
                required
              />
            </div>

            <button
              type="submit"
              className="w-full bg-blue-600 hover:bg-blue-500 text-white py-2.5 rounded-lg text-sm font-medium transition flex items-center justify-center gap-2 mt-2"
            >
              <ArrowUpDown className="w-4 h-4" /> Process Warehouse Transaction
            </button>
          </form>
        </div>

        {/* Right Column: Inventory Table */}
        <div className="lg:col-span-2 space-y-4">
          <div className="bg-slate-800/60 border border-slate-700 rounded-xl p-5">
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-lg font-semibold">Live Warehouse Stock</h2>
              <span className="text-xs text-slate-400">{items.length} Total Registered SKUs</span>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-left text-sm text-slate-300">
                <thead className="text-xs uppercase bg-slate-900/60 text-slate-400 border-b border-slate-700">
                  <tr>
                    <th className="px-4 py-3">SKU</th>
                    <th className="px-4 py-3">Item Details</th>
                    <th className="px-4 py-3">Location</th>
                    <th className="px-4 py-3">Current Qty</th>
                    <th className="px-4 py-3">Status</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-700/50">
                  {items.map((item) => (
                    <tr key={item.id} className="hover:bg-slate-700/30 transition">
                      <td className="px-4 py-3 font-mono text-blue-400 font-medium">{item.id}</td>
                      <td className="px-4 py-3">
                        <div className="font-medium text-slate-200">{item.name}</div>
                        <div className="text-xs text-slate-500">{item.category}</div>
                      </td>
                      <td className="px-4 py-3 font-mono text-xs">{item.bay}</td>
                      <td className="px-4 py-3 font-semibold">{item.qty}</td>
                      <td className="px-4 py-3">
                        <span
                          className={`text-xs px-2.5 py-1 rounded-full font-medium ${
                            item.status === 'In Stock'
                              ? 'bg-emerald-950 text-emerald-400 border border-emerald-800'
                              : item.status === 'Low Stock'
                              ? 'bg-amber-950 text-amber-400 border border-amber-800'
                              : 'bg-rose-950 text-rose-400 border border-rose-800'
                          }`}
                        >
                          {item.status}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>

      </main>
    </div>
  );
}