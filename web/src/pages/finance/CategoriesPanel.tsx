import { useState } from 'react'
import { Card, Confirm, Field, Icon, Modal } from '../../components/ui'
import { addCategory, deleteCategory } from '../../data/actions'
import { useDb } from '../../data/DbContext'
import { useCategories } from '../../data/hooks'
import type { Category, CategoryKind } from '../../domain/types'

export function CategoriesPanel() {
  const { db } = useDb()
  const categories = useCategories()
  const [adding, setAdding] = useState<{ kind: CategoryKind; parent?: Category } | undefined>()
  const [removing, setRemoving] = useState<Category | undefined>()

  const section = (kind: CategoryKind, title: string) => {
    const roots = categories.filter((c) => c.parentId === undefined && c.kind === kind)
    return (
      <Card title={title} action={<button className="btn small" onClick={() => setAdding({ kind })}><Icon name="plus" size={16} /> Categoria</button>}>
        <ul className="list">
          {roots.map((c) => (
            <li key={c.id} style={{ flexWrap: 'wrap' }}>
              <span className="dot"><Icon name="tag" size={18} /></span>
              <span className="grow"><b>{c.name}</b></span>
              <button className="btn small" onClick={() => setAdding({ kind, parent: c })}>+ Sub</button>
              <button className="icon-btn" aria-label={`Apagar ${c.name}`} onClick={() => setRemoving(c)}><Icon name="trash" size={18} /></button>
              {categories.filter((s) => s.parentId === c.id).map((s) => (
                <div key={s.id} className="row between" style={{ flexBasis: '100%', paddingLeft: 46 }}>
                  <span>{s.name}</span>
                  <button className="icon-btn" aria-label={`Apagar ${s.name}`} onClick={() => setRemoving(s)}><Icon name="trash" size={16} /></button>
                </div>
              ))}
            </li>
          ))}
        </ul>
      </Card>
    )
  }

  return (
    <div className="grid cols-2">
      {section('despesa', 'Despesas')}
      {section('receita', 'Receitas')}
      <NameDialog adding={adding} onClose={() => setAdding(undefined)} onSave={(name) => adding && addCategory(db, { name, kind: adding.kind, parentId: adding.parent?.id, icon: adding.parent?.icon })} />
      <Confirm open={!!removing} title={`Apagar ${removing?.name ?? ''}?`}
        text="Subcategorias e orçamentos dela também serão apagados. Os lançamentos ficam sem categoria."
        confirmLabel="Apagar" onConfirm={() => removing && deleteCategory(db, removing.id!)} onClose={() => setRemoving(undefined)} />
    </div>
  )
}

function NameDialog({ adding, onClose, onSave }: { adding?: { kind: CategoryKind; parent?: Category }; onClose: () => void; onSave: (name: string) => void }) {
  return (
    <Modal open={!!adding} title={adding?.parent ? `Subcategoria de ${adding.parent.name}` : 'Nova categoria'} onClose={onClose}>
      <NameBody onClose={onClose} onSave={onSave} />
    </Modal>
  )
}

function NameBody({ onClose, onSave }: { onClose: () => void; onSave: (name: string) => void }) {
  const [name, setName] = useState('')
  return (
    <form className="form" onSubmit={(e) => { e.preventDefault(); if (name.trim()) { onSave(name.trim()); onClose() } }}>
      <Field label="Nome"><input className="input" autoFocus value={name} onChange={(e) => setName(e.target.value)} /></Field>
      <div className="dlg-actions">
        <button type="button" className="btn" onClick={onClose}>Cancelar</button>
        <button type="submit" className="btn primary" disabled={!name.trim()}>Adicionar</button>
      </div>
    </form>
  )
}
