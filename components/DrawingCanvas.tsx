
import React, { useRef, useState, useEffect, useCallback, useImperativeHandle, forwardRef } from 'react';
import { Point, Path, ToolType } from '../types';
import { TOOL_WIDTHS } from '../constants';

interface DrawingCanvasProps {
  color: string;
  tool: ToolType;
  onSave: (svg: string) => void;
  isTimerRunning: boolean;
}

export interface DrawingCanvasRef {
  undo: () => void;
  exportSvg: () => string;
}

const DrawingCanvas = forwardRef<DrawingCanvasRef, DrawingCanvasProps>(({ color, tool, onSave, isTimerRunning }, ref) => {
  const [paths, setPaths] = useState<Path[]>([]);
  const [currentPath, setCurrentPath] = useState<Path | null>(null);
  const svgRef = useRef<SVGSVGElement>(null);

  // Increased vertical space for more immersive drawing
  const VIEW_WIDTH = 1000;
  const VIEW_HEIGHT = 1300; 

  useImperativeHandle(ref, () => ({
    undo: () => setPaths(prev => prev.slice(0, -1)),
    exportSvg: () => svgRef.current?.outerHTML || ''
  }));

  const getCoordinates = (e: React.MouseEvent | React.TouchEvent | any): Point | null => {
    if (!svgRef.current) return null;
    const rect = svgRef.current.getBoundingClientRect();
    const clientX = e.touches ? e.touches[0].clientX : e.clientX;
    const clientY = e.touches ? e.touches[0].clientY : e.clientY;
    
    const x = (clientX - rect.left) * (VIEW_WIDTH / rect.width);
    const y = (clientY - rect.top) * (VIEW_HEIGHT / rect.height);
    
    return { x, y };
  };

  const startDrawing = (e: any) => {
    if (!isTimerRunning) return;
    if (e.cancelable) e.preventDefault();
    
    const point = getCoordinates(e);
    if (!point) return;

    setCurrentPath({
      points: [point],
      color: tool === 'eraser' ? '#FFFFFF' : color,
      width: tool === 'marker' ? TOOL_WIDTHS.marker : (tool === 'eraser' ? TOOL_WIDTHS.eraser : TOOL_WIDTHS.pen),
      tool,
    });
  };

  const draw = (e: any) => {
    if (!isTimerRunning || !currentPath) return;
    if (e.cancelable) e.preventDefault();
    
    const point = getCoordinates(e);
    if (!point) return;

    setCurrentPath(prev => {
      if (!prev) return null;
      return { ...prev, points: [...prev.points, point] };
    });
  };

  const endDrawing = () => {
    if (currentPath) {
      setPaths(prev => [...prev, currentPath]);
      setCurrentPath(null);
    }
  };

  const renderPath = (path: Path, key: string | number) => {
    if (path.points.length < 1) return null;
    
    const d = path.points.length === 1 
      ? `M ${path.points[0].x} ${path.points[0].y} L ${path.points[0].x} ${path.points[0].y}`
      : `M ${path.points[0].x} ${path.points[0].y} ` + path.points.slice(1).map(p => `L ${p.x} ${p.y}`).join(' ');

    return (
      <path
        key={key}
        d={d}
        stroke={path.color}
        strokeWidth={path.width}
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
        style={{ opacity: path.tool === 'marker' ? 0.6 : 1 }}
      />
    );
  };

  const markerPaths = paths.filter(p => p.tool === 'marker');
  const otherPaths = paths.filter(p => p.tool !== 'marker');

  return (
    <div className="relative w-full aspect-[10/13] bg-white rounded-[2.5rem] shadow-2xl border-2 border-slate-200 overflow-hidden cursor-crosshair touch-none">
      <svg
        ref={svgRef}
        viewBox={`0 0 ${VIEW_WIDTH} ${VIEW_HEIGHT}`}
        className="w-full h-full"
        onMouseDown={startDrawing}
        onMouseMove={draw}
        onMouseUp={endDrawing}
        onMouseLeave={endDrawing}
        onTouchStart={startDrawing}
        onTouchMove={draw}
        onTouchEnd={endDrawing}
      >
        <rect width={VIEW_WIDTH} height={VIEW_HEIGHT} fill="white" />
        {markerPaths.map((p, i) => renderPath(p, `marker-${i}`))}
        {currentPath?.tool === 'marker' && renderPath(currentPath, 'current-marker')}
        
        {otherPaths.map((p, i) => renderPath(p, `other-${i}`))}
        {currentPath && currentPath.tool !== 'marker' && renderPath(currentPath, 'current-other')}
      </svg>
      
      {!isTimerRunning && paths.length === 0 && (
        <div className="absolute inset-0 flex flex-col items-center justify-center text-slate-300 font-medium bg-slate-50/50 backdrop-blur-[2px] pointer-events-none">
          <span className="text-9xl mb-8 opacity-20">🎨</span>
          <p className="text-2xl font-black uppercase tracking-widest text-slate-400">Waiting for start...</p>
        </div>
      )}
    </div>
  );
});

export default DrawingCanvas;
