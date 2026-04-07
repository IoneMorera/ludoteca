import { createApp } from 'vue'
import { createPinia } from 'pinia'
import router from './router'
import App from './App.vue'
import './style.css'

const app = createApp(App)

app.use(createPinia())
app.use(router)
console.log("API URL:", import.meta.env.VITE_API_URL)
app.mount('#app')
