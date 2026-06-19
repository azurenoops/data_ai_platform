/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './Pages/**/*.cshtml',
    './Pages/**/*.cshtml.cs',
    './wwwroot/js/**/*.js',
    './Program.cs'
  ],
  corePlugins: {
    preflight: false,
    container: false,
    visibility: false
  },
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter', 'Segoe UI', 'system-ui', 'sans-serif'],
        display: ['Lexend', 'Inter', 'Segoe UI', 'sans-serif'],
        mono: ['ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace']
      },
      colors: {
        tailspin: {
          50: '#f8fafc',
          100: '#f1f5f9',
          200: '#e2e8f0',
          300: '#cbd5e1',
          400: '#94a3b8',
          500: '#3b82f6',
          600: '#2563eb',
          700: '#1d4ed8',
          800: '#1e293b',
          900: '#0f172a'
        },
        seafoam: {
          500: '#2563eb',
          600: '#1d4ed8'
        }
      },
      boxShadow: {
        panel: '0 10px 30px rgba(15, 23, 42, 0.06)'
      }
    }
  },
  plugins: []
};
