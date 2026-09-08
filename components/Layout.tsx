
import React from 'react';
import { User } from '../types';

interface LayoutProps {
  children: React.ReactNode;
  user: User | null;
  onLogout: () => void;
  onNavigate: (view: 'dashboard' | 'draw' | 'vote' | 'profile') => void;
  currentView: string;
}

const Layout: React.FC<LayoutProps> = ({ children, user, onLogout, onNavigate, currentView }) => {
  return (
    <div className="min-h-screen flex flex-col bg-slate-50">
      <header className="bg-white/80 backdrop-blur-md border-b border-slate-200 sticky top-0 z-50">
        <div className="max-w-6xl mx-auto px-6 h-14 flex items-center justify-between">
          <button 
            onClick={() => onNavigate('dashboard')}
            className="flex items-center gap-2 group transition-transform active:scale-95"
          >
            <div className="w-8 h-8 bg-indigo-600 rounded-lg flex items-center justify-center text-white font-bold text-lg shadow-md group-hover:rotate-3 transition-transform">
              D
            </div>
            <span className="font-bold text-lg tracking-tight text-slate-900">DoodleDash</span>
          </button>

          {user && (
            <div className="flex items-center gap-2 sm:gap-6">
              <nav className="flex items-center gap-1">
                <button 
                  onClick={() => onNavigate('dashboard')}
                  className={`px-3 py-1.5 rounded-lg text-sm font-semibold transition-all ${currentView === 'dashboard' ? 'bg-indigo-600 text-white' : 'text-slate-500 hover:bg-slate-100 hover:text-slate-900'}`}
                >
                  Home
                </button>
                <button 
                  onClick={() => onNavigate('vote')}
                  className={`px-3 py-1.5 rounded-lg text-sm font-semibold transition-all ${currentView === 'vote' ? 'bg-indigo-600 text-white' : 'text-slate-500 hover:bg-slate-100 hover:text-slate-900'}`}
                >
                  Gallery
                </button>
              </nav>

              <div className="h-6 w-px bg-slate-200 hidden sm:block"></div>

              <div className="flex items-center gap-3">
                <button 
                  onClick={() => onNavigate('profile')}
                  className={`flex items-center gap-2 px-1.5 py-1 rounded-full border transition-all ${currentView === 'profile' ? 'bg-white border-indigo-200 ring-2 ring-indigo-50' : 'bg-transparent border-transparent hover:border-slate-200'}`}
                >
                  <img src={user.avatar} alt={user.name} className="w-7 h-7 rounded-full bg-slate-100" />
                  <span className="text-sm font-bold text-slate-700 hidden md:inline">{user.name}</span>
                </button>
                <button 
                  onClick={onLogout}
                  className="text-xs font-bold text-slate-400 hover:text-red-500 transition-colors uppercase tracking-wider"
                >
                  Exit
                </button>
              </div>
            </div>
          )}
        </div>
      </header>

      <main className="flex-1 max-w-6xl mx-auto w-full px-6 py-6">
        {children}
      </main>

      <footer className="py-8 text-center border-t border-slate-100 mt-12">
        <p className="text-slate-400 text-xs font-medium uppercase tracking-widest">© 2024 DoodleDash Studio</p>
      </footer>
    </div>
  );
};

export default Layout;
