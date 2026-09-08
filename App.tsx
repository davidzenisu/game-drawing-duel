
import React, { useState, useEffect, useCallback, useRef } from 'react';
import { HashRouter as Router } from 'react-router-dom';
import { User, Drawing, Prompt, ToolType } from './types';
import { db } from './services/db';
import { getDailyPrompt } from './services/geminiService';
import Layout from './components/Layout';
import DrawingCanvas, { DrawingCanvasRef } from './components/DrawingCanvas';
import { COLORS, DRAWING_TIME_LIMIT, DAILY_VOTE_LIMIT } from './constants';

// --- Sub-Views ---

const LoginView = ({ onLogin }: { onLogin: (name: string, email: string) => void }) => {
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');

  return (
    <div className="min-h-screen flex items-center justify-center bg-slate-50 p-6">
      <div className="max-w-md w-full p-8 sm:p-10 bg-white rounded-[2.5rem] shadow-2xl border border-slate-200">
        <div className="text-center mb-10">
          <div className="w-20 h-20 bg-indigo-600 rounded-3xl flex items-center justify-center text-white font-bold text-4xl shadow-xl mx-auto mb-6 transform -rotate-3">D</div>
          <h1 className="text-3xl font-black text-slate-900 tracking-tight">DoodleDash</h1>
          <p className="text-slate-400 font-bold text-sm uppercase tracking-widest mt-2">The 60-Second Challenge</p>
        </div>
        <div className="space-y-6">
          <div>
            <label className="block text-xs font-black text-slate-400 uppercase tracking-widest mb-2 ml-1">Artist Name</label>
            <input 
              type="text" 
              value={name} 
              onChange={e => setName(e.target.value)}
              className="w-full px-5 py-4 bg-slate-50 border border-slate-200 rounded-2xl focus:ring-4 focus:ring-indigo-500/10 focus:border-indigo-500 transition-all outline-none font-bold text-slate-800 text-lg"
              placeholder="e.g. Picasso"
            />
          </div>
          <div>
            <label className="block text-xs font-black text-slate-400 uppercase tracking-widest mb-2 ml-1">Email</label>
            <input 
              type="email" 
              value={email} 
              onChange={e => setEmail(e.target.value)}
              className="w-full px-5 py-4 bg-slate-50 border border-slate-200 rounded-2xl focus:ring-4 focus:ring-indigo-500/10 focus:border-indigo-500 transition-all outline-none font-bold text-slate-800 text-lg"
              placeholder="you@studio.com"
            />
          </div>
          <button 
            disabled={!name || !email}
            onClick={() => onLogin(name, email)}
            className="w-full bg-indigo-600 text-white py-5 rounded-2xl font-black text-xl hover:bg-indigo-700 transition-all shadow-xl active:scale-95 disabled:opacity-40"
          >
            ENTER STUDIO
          </button>
        </div>
      </div>
    </div>
  );
};

const DashboardView = ({ user, prompt, onNavigate }: { user: User, prompt: Prompt | null, onNavigate: any }) => {
  const today = new Date().toISOString().split('T')[0];
  const hasDrawnToday = user.lastDrawDate === today;
  const votesRemaining = DAILY_VOTE_LIMIT - user.votedDrawingIds.length;

  return (
    <div className="space-y-8 max-w-5xl mx-auto animate-in fade-in slide-in-from-bottom-4 duration-500">
      <div className="bg-indigo-600 rounded-[2.5rem] p-10 text-white shadow-2xl relative overflow-hidden flex flex-col md:flex-row md:items-center justify-between gap-10">
        <div className="relative z-10">
          <h2 className="text-4xl font-black mb-2">Hey, {user.name}!</h2>
          <p className="text-indigo-100 text-xl font-medium opacity-90">Ready for your daily masterpiece?</p>
        </div>
        <div className="relative z-10 shrink-0">
          {!hasDrawnToday ? (
            <button 
              onClick={() => onNavigate('draw')}
              className="bg-white text-indigo-700 px-10 py-5 rounded-2xl font-black text-xl hover:bg-indigo-50 transition-all shadow-xl flex items-center gap-3 active:scale-95"
            >
              <span>⚡</span> START CHALLENGE
            </button>
          ) : (
            <div className="bg-white/10 border border-white/20 px-8 py-5 rounded-2xl font-bold text-lg backdrop-blur-sm">
              Locked in for today! 🎨
            </div>
          )}
        </div>
        <div className="absolute top-0 right-0 w-64 h-64 bg-indigo-400/20 rounded-full blur-[80px] -mr-20 -mt-20 animate-pulse"></div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
        <div className="bg-white p-8 rounded-3xl border border-slate-200 shadow-sm flex flex-col justify-center items-center text-center">
          <p className="text-xs font-black text-slate-400 uppercase tracking-[0.2em] mb-4">Prompt of the Day</p>
          <div className="bg-amber-50 border-2 border-amber-200 border-dashed p-6 rounded-2xl w-full">
            <span className="text-2xl font-hand text-amber-900">
              {prompt?.text || "Generating..."}
            </span>
          </div>
        </div>
        
        <div className="bg-white p-8 rounded-3xl border border-slate-200 shadow-sm flex flex-col justify-center items-center text-center">
          <p className="text-xs font-black text-slate-400 uppercase tracking-[0.2em] mb-2">Your Doodles</p>
          <span className="text-5xl font-black text-indigo-600">{user.drawingsDone}</span>
        </div>

        <div className="bg-white p-8 rounded-3xl border border-slate-200 shadow-sm flex flex-col justify-center items-center text-center">
          <p className="text-xs font-black text-slate-400 uppercase tracking-[0.2em] mb-2">Daily Votes</p>
          <span className="text-5xl font-black text-emerald-500">{votesRemaining}</span>
        </div>
      </div>
    </div>
  );
};

const VoteView = ({ drawings, user, onVote }: { drawings: Drawing[], user: User, onVote: (id: string, dir: number) => void }) => {
  const voteableDrawings = drawings.filter(d => !user.votedDrawingIds.includes(d.id));
  const [currentIndex, setCurrentIndex] = useState(0);
  const votesRemaining = DAILY_VOTE_LIMIT - user.votedDrawingIds.length;
  
  const handleVoteAction = (dir: number) => {
    if (votesRemaining <= 0 || currentIndex >= voteableDrawings.length) return;
    onVote(voteableDrawings[currentIndex].id, dir);
    setCurrentIndex(prev => prev + 1);
  };

  const currentDrawing = voteableDrawings[currentIndex];

  if (votesRemaining <= 0 || !currentDrawing) {
    return (
      <div className="max-w-xl mx-auto py-16 text-center bg-white rounded-[3rem] border border-slate-200 shadow-2xl p-12 animate-in fade-in zoom-in duration-500">
        <div className="text-6xl mb-6">🏆</div>
        <h2 className="text-3xl font-black mb-4">Master Critic</h2>
        <p className="text-slate-500 text-lg mb-10 leading-relaxed">
          {votesRemaining <= 0 
            ? "You've shared all your gold stars for today! Come back tomorrow to judge new talent." 
            : "The gallery is empty! Check back later for new daily submissions."}
        </p>
        <button 
          onClick={() => window.location.hash = '#/'}
          className="bg-indigo-600 text-white px-10 py-4 rounded-2xl font-black text-lg hover:bg-indigo-700 shadow-xl"
        >
          BACK TO STUDIO
        </button>
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto space-y-8 animate-in zoom-in-95 duration-500 pb-12">
      <div className="flex items-center justify-between">
        <h2 className="text-3xl font-black text-slate-900">Gallery Floor</h2>
        <span className="text-sm font-black text-emerald-600 bg-emerald-50 px-4 py-2 rounded-xl border border-emerald-100">
          {votesRemaining} VOTES LEFT
        </span>
      </div>

      <div className="bg-white p-6 rounded-[2.5rem] shadow-2xl border border-slate-200">
        <div className="aspect-[10/13] bg-slate-50 rounded-3xl flex items-center justify-center border border-slate-100 overflow-hidden mb-6">
           <div className="w-full h-full flex items-center justify-center p-2" dangerouslySetInnerHTML={{ __html: currentDrawing.svgData }} />
        </div>
        <div className="text-center px-4">
          <p className="text-3xl font-hand text-slate-800 mb-2">"{currentDrawing.prompt}"</p>
          <div className="flex items-center justify-center gap-2 text-slate-400">
            <span className="w-6 h-px bg-slate-200"></span>
            <span className="text-xs font-black uppercase tracking-widest">Artist: {currentDrawing.userName}</span>
            <span className="w-6 h-px bg-slate-200"></span>
          </div>
        </div>
      </div>

      <div className="flex gap-6">
        <button 
          onClick={() => handleVoteAction(-1)}
          className="flex-1 bg-white border-2 border-slate-200 py-6 rounded-3xl font-black text-xl text-slate-400 hover:text-red-500 hover:border-red-200 transition-all active:scale-95 shadow-lg"
        >
          SKIP IT 👎
        </button>
        <button 
          onClick={() => handleVoteAction(1)}
          className="flex-1 bg-indigo-600 text-white py-6 rounded-3xl font-black text-xl shadow-2xl hover:bg-indigo-700 transition-all active:scale-95"
        >
          LOVE IT! 🔥
        </button>
      </div>
    </div>
  );
};

const App: React.FC = () => {
  const [user, setUser] = useState<User | null>(db.getUser());
  const [prompt, setPrompt] = useState<Prompt | null>(null);
  const [drawings, setDrawings] = useState<Drawing[]>(db.getDrawings());
  const [currentView, setCurrentView] = useState<'dashboard' | 'draw' | 'vote' | 'profile'>('dashboard');
  
  const canvasRef = useRef<DrawingCanvasRef>(null);
  const [timeLeft, setTimeLeft] = useState(DRAWING_TIME_LIMIT);
  const [isDrawingActive, setIsDrawingActive] = useState(false);
  const [activeColor, setActiveColor] = useState(COLORS[0]);
  const [activeTool, setActiveTool] = useState<ToolType>('pen');

  const fetchPrompt = useCallback(async () => {
    const today = new Date().toISOString().split('T')[0];
    const saved = db.getPrompts();
    const existing = saved.find(p => p.date === today);
    if (existing) {
      setPrompt(existing);
    } else {
      const text = await getDailyPrompt();
      const newPrompt = { text, date: today };
      db.savePrompt(newPrompt);
      setPrompt(newPrompt);
    }
  }, []);

  useEffect(() => { fetchPrompt(); }, [fetchPrompt]);

  useEffect(() => {
    let interval: any;
    if (isDrawingActive && timeLeft > 0) {
      interval = setInterval(() => setTimeLeft(prev => prev - 1), 1000);
    } else if (timeLeft === 0 && isDrawingActive) {
      finishDrawing();
    }
    return () => clearInterval(interval);
  }, [isDrawingActive, timeLeft]);

  const handleLogin = (name: string, email: string) => {
    const newUser: User = {
      id: Math.random().toString(36).substr(2, 9),
      name,
      email,
      avatar: `https://api.dicebear.com/7.x/pixel-art/svg?seed=${name}`,
      drawingsDone: 0,
      lastDrawDate: null,
      lastVoteDate: new Date().toISOString().split('T')[0],
      votedDrawingIds: []
    };
    db.saveUser(newUser);
    setUser(newUser);
  };

  const handleLogout = () => {
    setUser(null);
    localStorage.removeItem('doodledash_v2_user');
  };

  const finishDrawing = () => {
    if (!canvasRef.current || !user || !prompt) return;
    const svg = canvasRef.current.exportSvg();
    const today = new Date().toISOString().split('T')[0];
    
    const newDrawing: Drawing = {
      id: Math.random().toString(36).substr(2, 9),
      userId: user.id,
      userName: user.name,
      prompt: prompt.text,
      svgData: svg,
      votes: 0,
      createdAt: new Date().toISOString()
    };

    db.saveDrawing(newDrawing);
    const updatedUser = { ...user, drawingsDone: user.drawingsDone + 1, lastDrawDate: today };
    db.saveUser(updatedUser);
    
    setUser(updatedUser);
    setDrawings(prev => [...prev, newDrawing]);
    setIsDrawingActive(false);
    setCurrentView('dashboard');
  };

  const handleVote = (id: string, value: number) => {
    if (!user) return;
    db.voteDrawing(id, value);
    const updatedUser = { ...user, votedDrawingIds: [...user.votedDrawingIds, id] };
    db.saveUser(updatedUser);
    setUser(updatedUser);
  };

  if (!user) return <LoginView onLogin={handleLogin} />;

  return (
    <Router>
      <Layout 
        user={user} 
        onLogout={handleLogout} 
        onNavigate={(v) => { setIsDrawingActive(false); setTimeLeft(DRAWING_TIME_LIMIT); setCurrentView(v); }}
        currentView={currentView}
      >
        {currentView === 'dashboard' && <DashboardView user={user} prompt={prompt} onNavigate={setCurrentView} />}
        
        {currentView === 'draw' && prompt && (
          <div className="max-w-4xl mx-auto space-y-6 pb-20">
            {/* Enhanced Drawing Toolbar */}
            <div className="bg-white/95 backdrop-blur-md p-4 sm:p-5 rounded-[2rem] border border-slate-200 shadow-xl sticky top-2 z-40 flex flex-wrap items-center justify-between gap-4 transition-all">
              <div className="flex items-center gap-4">
                <div className={`w-14 h-14 sm:w-16 sm:h-16 rounded-2xl flex items-center justify-center font-black text-xl sm:text-2xl shadow-inner transition-all ${timeLeft < 10 ? 'bg-red-500 text-white animate-pulse' : 'bg-slate-900 text-white'}`}>
                  {timeLeft}
                </div>
                <div className="hidden sm:block">
                  <p className="text-xs font-black uppercase tracking-widest text-slate-400 mb-0.5">Prompt</p>
                  <p className="font-hand text-xl text-indigo-600 truncate max-w-[200px]">"{prompt.text}"</p>
                </div>
              </div>

              <div className="flex items-center gap-2 bg-slate-50 p-1.5 rounded-2xl border border-slate-100 overflow-x-auto no-scrollbar">
                <button 
                  onClick={() => setActiveTool('pen')} 
                  className={`px-4 py-2 sm:px-6 sm:py-3 rounded-xl text-sm sm:text-base font-black transition-all ${activeTool === 'pen' ? 'bg-indigo-600 text-white shadow-lg' : 'hover:bg-white text-slate-500'}`}
                >✏️ Pen</button>
                <button 
                  onClick={() => setActiveTool('marker')} 
                  className={`px-4 py-2 sm:px-6 sm:py-3 rounded-xl text-sm sm:text-base font-black transition-all ${activeTool === 'marker' ? 'bg-indigo-600 text-white shadow-lg' : 'hover:bg-white text-slate-500'}`}
                >🖍️ Marker</button>
                <button 
                  onClick={() => setActiveTool('eraser')} 
                  className={`px-4 py-2 sm:px-6 sm:py-3 rounded-xl text-sm sm:text-base font-black transition-all ${activeTool === 'eraser' ? 'bg-indigo-600 text-white shadow-lg' : 'hover:bg-white text-slate-500'}`}
                >🧽 Eraser</button>
                <div className="w-px h-8 bg-slate-200 mx-1"></div>
                <button 
                   onClick={() => canvasRef.current?.undo()} 
                   className="p-2 sm:p-3 hover:bg-white rounded-xl text-xl transition-transform active:scale-90" 
                   title="Undo"
                >↩️</button>
              </div>

              <div className="flex items-center gap-3">
                <div className="flex items-center gap-1.5 bg-slate-50 p-1.5 rounded-2xl border border-slate-100 overflow-x-auto no-scrollbar">
                  {COLORS.slice(0, 6).map(c => (
                    <button 
                      key={c}
                      onClick={() => { setActiveColor(c); if(activeTool === 'eraser') setActiveTool('pen'); }}
                      className={`w-8 h-8 sm:w-10 sm:h-10 rounded-xl border-4 transition-all hover:scale-110 active:scale-90 ${activeColor === c && activeTool !== 'eraser' ? 'border-indigo-600 ring-4 ring-indigo-50' : 'border-white shadow-sm'}`}
                      style={{ backgroundColor: c }}
                    />
                  ))}
                </div>
                <button 
                  onClick={finishDrawing} 
                  disabled={!isDrawingActive}
                  className="bg-emerald-500 text-white px-6 py-3 sm:px-8 sm:py-4 rounded-2xl font-black text-base sm:text-lg hover:bg-emerald-600 disabled:opacity-20 transition-all shadow-xl active:scale-95"
                >FINISH</button>
              </div>
            </div>

            {/* Canvas Area */}
            <div className="relative group">
              <DrawingCanvas 
                ref={canvasRef}
                color={activeColor} 
                tool={activeTool} 
                isTimerRunning={isDrawingActive} 
                onSave={finishDrawing}
              />
              
              {!isDrawingActive && (
                <div className="absolute inset-0 bg-slate-900/40 backdrop-blur-md rounded-[2.5rem] flex items-center justify-center z-10 transition-opacity">
                  <div className="bg-white p-10 sm:p-12 rounded-[3rem] shadow-2xl border border-slate-100 text-center max-w-md mx-4 transform transition-all animate-in fade-in zoom-in duration-300">
                    <div className="w-20 h-20 bg-amber-100 rounded-3xl flex items-center justify-center text-4xl mb-6 mx-auto">🎨</div>
                    <h3 className="text-3xl font-black mb-4">Daily Dash</h3>
                    <p className="text-slate-500 text-lg mb-8 leading-relaxed">
                      You've got 60 seconds to draw: <br/>
                      <span className="text-2xl font-hand text-indigo-600 font-bold block mt-2">"{prompt.text}"</span>
                    </p>
                    <button 
                      onClick={() => setIsDrawingActive(true)}
                      className="w-full bg-slate-900 text-white py-5 rounded-2xl font-black text-xl hover:bg-black transition-all active:scale-95 shadow-2xl"
                    >
                      LET'S GO! ⚡
                    </button>
                  </div>
                </div>
              )}
            </div>
          </div>
        )}

        {currentView === 'vote' && <VoteView drawings={drawings} user={user} onVote={handleVote} />}

        {currentView === 'profile' && (
          <div className="max-w-2xl mx-auto bg-white p-8 sm:p-12 rounded-[3rem] border border-slate-200 shadow-2xl animate-in fade-in slide-in-from-bottom-8 duration-500">
            <h2 className="text-4xl font-black text-center mb-10">Artist Profile</h2>
            <div className="flex flex-col items-center mb-12">
              <div className="relative">
                <img src={user.avatar} className="w-32 h-32 rounded-[2.5rem] bg-slate-50 border-4 border-white shadow-2xl mb-6" alt="Avatar" />
                <div className="absolute -bottom-2 -right-2 w-10 h-10 bg-indigo-600 rounded-full border-4 border-white flex items-center justify-center text-white text-xs font-black">LVL {Math.floor(user.drawingsDone / 5) + 1}</div>
              </div>
              <p className="text-3xl font-black text-slate-900">{user.name}</p>
              <p className="text-slate-400 font-bold uppercase tracking-widest text-xs mt-1">{user.email}</p>
            </div>
            
            <div className="grid grid-cols-2 gap-6 mb-12">
              <div className="p-6 bg-slate-50 rounded-3xl text-center border border-slate-100">
                <p className="text-xs font-black text-slate-400 uppercase tracking-widest mb-2">Total Doodles</p>
                <p className="text-4xl font-black text-indigo-600">{user.drawingsDone}</p>
              </div>
              <div className="p-6 bg-slate-50 rounded-3xl text-center border border-slate-100">
                <p className="text-xs font-black text-slate-400 uppercase tracking-widest mb-2">Rank</p>
                <p className="text-4xl font-black text-amber-500">
                  {user.drawingsDone < 5 ? "Novice" : user.drawingsDone < 20 ? "Amateur" : "Master"}
                </p>
              </div>
            </div>

            <button 
              onClick={handleLogout}
              className="w-full bg-red-50 text-red-500 py-5 rounded-2xl font-black text-xl hover:bg-red-100 transition-all active:scale-95 flex items-center justify-center gap-3"
            >
              LOGOUT STUDIO 🚪
            </button>
          </div>
        )}
      </Layout>
    </Router>
  );
};

export default App;
