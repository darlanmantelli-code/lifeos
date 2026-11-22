import { useEffect, useState } from 'react'
import { BrandLockup, BRAND } from '../brand/Logo'
import { Card, Confirm, Field, Modal, Seg } from '../components/ui'
import { BackupError, exportBackup, parseBackup, restoreBackup, wipe, type BackupFile } from '../data/backup'
import { ensureDefaults } from '../data/actions'
import { useDb } from '../data/DbContext'

type Theme = 'auto' | 'light' | 'dark'

export function applyTheme(t: Theme) {
  if (t === 'auto') document.documentElement.removeAttribute('data-theme')
  else document.documentElement.setAttribute('data-theme', t)
}

interface InstallEvent extends Event { prompt(): Promise<void> }

export function Settings() {
  const { db, demo, setDemo } = useDb()
  const [theme, setTheme] = useState<Theme>(() => (localStorage.getItem('livo.theme') as Theme) || 'auto')
  const [message, setMessage] = useState('')
  const [pending, setPending] = useState<BackupFile | undefined>()
  const [wiping, setWiping] = useState(false)
  const [persisted, setPersisted] = useState<boolean | undefined>()
  const [install, setInstall] = useState<InstallEvent | undefined>()

  useEffect(() => {
    void navigator.storage?.persisted?.().then(setPersisted)
    const onPrompt = (e: Event) => { e.preventDefault(); setInstall(e as InstallEvent) }
    window.addEventListener('beforeinstallprompt', onPrompt)
    return () => window.removeEventListener('beforeinstallprompt', onPrompt)
  }, [])

  const chooseTheme = (t: Theme) => { setTheme(t); localStorage.setItem('livo.theme', t); applyTheme(t) }

  async function doExport() {
    const file = await exportBackup(db)
    const blob = new Blob([JSON.stringify(file, null, 2)], { type: 'application/json' })
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob)
    a.download = `livo-backup-${new Date().toISOString().slice(0, 10)}.json`
    a.click()
    URL.revokeObjectURL(a.href)
    setMessage('Backup exportado. Guarde o arquivo em local seguro: ele não é criptografado.')
  }

  async function pickFile(file: File) {
    setMessage('')
    try {
      setPending(parseBackup(await file.text()))
    } catch (e) {
      setMessage(e instanceof BackupError ? e.message : 'Não foi possível ler o arquivo.')
    }
  }

  return (
    <>
      <div className="page-head"><div><h1>Configurações</h1><p className="sub">Aparência, seus dados e privacidade.</p></div></div>
      <div className="stack">
        <Card title="Aparência">
          <Seg label="Tema" value={theme} onChange={chooseTheme} options={[['auto', 'Automático'], ['light', 'Claro'], ['dark', 'Escuro']]} />
        </Card>

        <Card title="Seus dados">
          {demo && <p className="note-box" style={{ marginBottom: 12 }}>Modo demonstração ativo: estas ações valem só para os dados fictícios.</p>}
          <div className="row wrap">
            <button className="btn" onClick={doExport}>Exportar backup (JSON)</button>
            <label className="btn" style={{ cursor: 'pointer' }}>
              Restaurar backup…
              <input type="file" accept="application/json,.json" className="sr" onChange={(e) => { const f = e.target.files?.[0]; if (f) void pickFile(f); e.target.value = '' }} />
            </label>
            <button className="btn danger" disabled={demo} onClick={() => setWiping(true)}>Apagar todos os dados</button>
          </div>
          <p className="muted small" style={{ marginTop: 10 }}>
            O backup tem o mesmo formato do app livo para iPhone: exporte lá e restaure aqui, ou o contrário. Os dados ficam só neste navegador
            (nada é enviado a servidor). {persisted === false && 'O navegador ainda não garantiu o armazenamento permanente; faça backups com frequência.'}
          </p>
          {message && <p className="note-box" role="status" style={{ marginTop: 10 }}>{message}</p>}
        </Card>

        <Card title="Modo demonstração">
          <label className="row"><input type="checkbox" checked={demo} onChange={(e) => setDemo(e.target.checked)} style={{ width: 22, height: 22 }} />
            <span>Mostrar dados fictícios para conhecer o app</span></label>
          <p className="muted small" style={{ marginTop: 8 }}>Seus dados reais não são tocados e voltam ao desativar.</p>
        </Card>

        {install && (
          <Card title="Instalar o livo">
            <p className="muted" style={{ marginBottom: 10 }}>Instale como aplicativo para abrir em janela própria e funcionar offline.</p>
            <button className="btn primary" onClick={() => install.prompt()}>Instalar</button>
          </Card>
        )}

        <Card title="Sobre">
          <div className="stack">
            <BrandLockup height={26} />
            <p>{BRAND.headline} {BRAND.tagline}</p>
            <p className="muted small">Seus dados ficam neste navegador. Nada é enviado sem uma ação sua e nenhuma conta bancária é acessada.</p>
          </div>
        </Card>
      </div>

      <Confirm open={!!pending} title="Substituir todos os dados pelo backup?" text="Os registros atuais deste navegador serão apagados e trocados pelos do arquivo."
        confirmLabel="Restaurar" onClose={() => setPending(undefined)}
        onConfirm={async () => { if (pending) { await restoreBackup(db, pending); setMessage('Backup restaurado.') } }} />
      <WipeDialog open={wiping} onClose={() => setWiping(false)} onWipe={async () => { await wipe(db); await ensureDefaults(db); setMessage('Todos os dados foram apagados.') }} />
    </>
  )
}

function WipeDialog({ open, onClose, onWipe }: { open: boolean; onClose: () => void; onWipe: () => void }) {
  return (
    <Modal open={open} title="Apagar todos os dados?" onClose={onClose}>
      <WipeBody onClose={onClose} onWipe={onWipe} />
    </Modal>
  )
}

function WipeBody({ onClose, onWipe }: { onClose: () => void; onWipe: () => void }) {
  const [text, setText] = useState('')
  const ok = text.trim().toUpperCase() === 'APAGAR'
  return (
    <form className="form" onSubmit={(e) => { e.preventDefault(); if (ok) { onWipe(); onClose() } }}>
      <p className="muted">Remove todos os registros deste navegador. Não pode ser desfeito; exporte antes se quiser guardar.</p>
      <Field label="Digite APAGAR para confirmar"><input className="input" autoFocus value={text} onChange={(e) => setText(e.target.value)} /></Field>
      <div className="dlg-actions"><button type="button" className="btn" onClick={onClose}>Cancelar</button><button type="submit" className="btn primary" disabled={!ok}>Apagar tudo</button></div>
    </form>
  )
}
