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
        sans: ['Outfit', 'Segoe UI', 'sans-serif'],
        mono: ['Space Mono', 'ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace']
      },
      colors: {
        tailspin: {
          50: '#f5fbff',
          100: '#e8f3ff',
          200: '#d6e7fb',
          300: '#b7d4f6',
          400: '#84b6ea',
          500: '#5b97d9',
          600: '#3f78bc',
          700: '#2f5d97',
          800: '#24456d',
          900: '#1a2f4b'
        },
        seafoam: {
          500: '#0f8c84',
          600: '#0b6f68'
        }
      },
      boxShadow: {
        panel: '0 14px 34px rgba(24, 45, 92, 0.11)'
      }
    }
  },
  plugins: []
};
