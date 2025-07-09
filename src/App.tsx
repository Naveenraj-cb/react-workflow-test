import React, { useState } from 'react';
import logo from './logo.svg';
import './App.css';

function App() {
  const [selectedColor, setSelectedColor] = useState('#282c34');

  const colorOptions = [
    { name: 'Default', value: '#282c34' },
    { name: 'Blue', value: '#1e3a8a' },
    { name: 'Green', value: '#166534' },
    { name: 'Purple', value: '#7c3aed' },
    { name: 'Red', value: '#dc2626' }
  ];

  const handleColorChange = (color: string) => {
    setSelectedColor(color);
  };

  return (
    <div className="App">
      <header className="App-header" style={{ backgroundColor: selectedColor }}>
        <img src={logo} className="App-logo" alt="logo" />
        <p>
          Edit <code>src/App.tsx</code> and save to reload.
        </p>
        <a
          className="App-link"
          href="https://reactjs.org"
          target="_blank"
          rel="noopener noreferrer"
        >
          Learn React
        </a>
      </header>
      <div className="color-dropdown">
        <select 
          value={selectedColor} 
          onChange={(e) => handleColorChange(e.target.value)}
          className="color-selector"
        >
          {colorOptions.map((option) => (
            <option key={option.value} value={option.value}>
              {option.name}
            </option>
          ))}
        </select>
      </div>
    </div>
  );
}

export default App;
