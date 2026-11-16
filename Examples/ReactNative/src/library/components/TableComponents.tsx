import { Children, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { Modal, Platform, Pressable, ScrollView, Text, TextInput, View } from 'react-native';
import { useGetFieldValue, useIsStreaming, useSetFieldValue, useTriggerAction, type ComponentRenderer } from '@openuidev/react-lang';
import ActionButton from '../../platform/ActionButton';
import { normalizeError } from '../../runtime/errors';
import { useDocumentInteraction } from '../../runtime/interaction';
import { useOpenUITheme } from '../theme';
import { useNativeContentPolicy } from './contentPolicy';
import { NativeDateEditor } from './FormComponents';
import { useFieldGuard } from './useNativeField';

type ColumnType = 'text' | 'number' | 'date-single' | 'select' | 'url';
type Option = { value: string; label: string };
type Column = { key: string; header: string; type: ColumnType; width?: number; options: Option[] };
type Row = { id: string; values: (string | number)[] };
const PAGE_SIZE = 10;
const string = (value: unknown) => typeof value === 'string' ? value : '';
const array = (value: unknown): unknown[] => Array.isArray(value) ? value : [];
const object = (value: unknown): Record<string, unknown> | undefined =>
  value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
const cellText = (value: unknown) => typeof value === 'string' || typeof value === 'number' ? String(value) : '';
const columnWidth = (value: unknown) => typeof value === 'number' && Number.isFinite(value) && value > 0
  ? Math.max(112, Math.min(640, value)) : 160;

function TableAction({ label, onPress, disabled = false, primary = false, busy = false }: {
  label: string; onPress: () => void; disabled?: boolean; primary?: boolean; busy?: boolean;
}) {
  return <ActionButton label={label} onPress={onPress} disabled={disabled} busy={busy}
    variant={primary ? 'primary' : 'secondary'} type="normal" size="small" />;
}

function Pagination({ page, count, disabled, onPage }: {
  page: number; count: number; disabled: boolean; onPage: (page: number) => void;
}) {
  const theme = useOpenUITheme();
  const total = Math.max(1, Math.ceil(count / PAGE_SIZE));
  if (total <= 1) return null;
  return <View style={{ flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'flex-end', gap: 8 }}>
    <TableAction label="上一页" disabled={disabled || page === 0} onPress={() => onPage(Math.max(0, page - 1))} />
    <Text accessibilityLiveRegion="polite" style={{ color: theme.muted, fontSize: 13 }}>{page + 1} / {total}</Text>
    <TableAction label="下一页" disabled={disabled || page >= total - 1} onPress={() => onPage(Math.min(total - 1, page + 1))} />
  </View>;
}

function NativeCell({ value, renderNode }: { value: unknown; renderNode: (value: unknown) => ReactNode }) {
  const theme = useOpenUITheme();
  const item = object(value);
  if (Array.isArray(value) || item?.type === 'element') {
    return <>{Children.map(renderNode(value), child => typeof child === 'string' || typeof child === 'number'
      ? <Text selectable style={{ color: theme.ink, fontSize: 14, lineHeight: 21 }}>{child}</Text> : child)}</>;
  }
  const display = value == null ? '—' : item ? JSON.stringify(item) : String(value);
  return <Text selectable style={{ color: theme.ink, fontSize: 14, lineHeight: 22 }}>{display}</Text>;
}

const Table: ComponentRenderer = ({ props, renderNode }) => {
  const theme = useOpenUITheme();
  const streaming = useIsStreaming();
  const { canInteract } = useDocumentInteraction();
  const columns = array(props.columns).flatMap(value => {
    const item = object(value);
    const column = item?.type === 'element' && item.typeName === 'Col' ? object(item.props) : item;
    return column ? [{ label: string(column.label), data: array(column.data), type: string(column.type) }] : [];
  });
  const identity = JSON.stringify(columns.map(column => [column.label, column.type, column.data]));
  const guard = useFieldGuard(identity);
  const [page, setPage] = useState(0);
  let count = 0;
  for (const column of columns) count = Math.max(count, column.data.length);
  const safePage = Math.min(page, Math.max(0, Math.ceil(count / PAGE_SIZE) - 1));
  if (!columns.length) return <Text style={{ color: theme.muted, fontSize: 14 }}>{streaming ? '正在生成表格…' : '暂无列定义'}</Text>;
  const start = safePage * PAGE_SIZE;
  return <View testID="openui-table" style={{ gap: 10, minWidth: 0 }}>
    <ScrollView horizontal nestedScrollEnabled keyboardShouldPersistTaps="handled">
      <View style={{ borderWidth: 1, borderColor: theme.border, borderRadius: 12, overflow: 'hidden' }}>
        <View style={{ flexDirection: 'row', backgroundColor: theme.surfaceMuted }}>
          {columns.map((column, index) => <View key={index} style={{ width: 176, padding: 12, justifyContent: 'center' }}>
            <Text accessibilityRole="header" style={{ color: theme.ink, fontSize: 14, lineHeight: 21,
              fontWeight: '600', textAlign: column.type === 'number' ? 'right' : 'left' }}>{column.label}</Text>
          </View>)}
        </View>
        {Array.from({ length: Math.min(PAGE_SIZE, count - start) }, (_, offset) => {
          const row = start + offset;
          return <View key={row} style={{ flexDirection: 'row', alignItems: 'stretch',
            borderTopWidth: 0.5, borderColor: theme.border, backgroundColor: theme.surface }}>
            {columns.map((column, index) => <View key={index} style={{ width: 176, padding: 12,
              minHeight: theme.controlMinHeight, justifyContent: 'center',
              alignItems: column.type === 'number' ? 'flex-end' : 'stretch' }}>
              <NativeCell value={column.data[row]} renderNode={renderNode} />
            </View>)}
          </View>;
        })}
      </View>
    </ScrollView>
    {!count ? <Text style={{ color: theme.muted, fontSize: 14 }}>{streaming ? '正在生成表格…' : '暂无数据'}</Text> : null}
    <Pagination page={safePage} count={count} disabled={streaming || !canInteract()}
      onPage={next => { if (guard()) setPage(next); }} />
  </View>;
};

function readColumns(value: unknown): { columns: Column[]; issue?: string } {
  const columns: Column[] = [];
  let issue: string | undefined;
  for (const entry of array(value)) {
    const source = object(entry);
    const type = source?.type;
    if (!source || typeof source.key !== 'string' || typeof source.header !== 'string'
      || !['text', 'number', 'date-single', 'select', 'url'].includes(String(type))) {
      issue = '列定义不完整或包含不支持的编辑类型。'; continue;
    }
    const options: Option[] = [];
    for (const item of array(source.options)) {
      const option = object(item);
      if (!option || typeof option.value !== 'string' || typeof option.label !== 'string') {
        issue = '选项需要字符串 value 和 label。'; continue;
      }
      options.push({ value: option.value, label: option.label });
    }
    columns.push({ key: source.key, header: source.header, type: type as ColumnType,
      width: typeof source.width === 'number' ? source.width : undefined, options });
  }
  return { columns, issue };
}

function readRows(value: unknown): { rows: Row[]; issue?: string } {
  const rows: Row[] = [];
  let issue: string | undefined;
  if (!Array.isArray(value)) return { rows, issue: '表格数据必须是包含 id 和 values 的行数组。' };
  for (const entry of value) {
    const source = object(entry);
    if (!source || typeof source.id !== 'string' || !Array.isArray(source.values)
      || !source.values.every(value => typeof value === 'string' || (typeof value === 'number' && Number.isFinite(value)))) {
      issue = '每行需要字符串 id，以及字符串或有限数字组成的 values。'; continue;
    }
    rows.push({ id: source.id, values: [...source.values] as (string | number)[] });
  }
  return { rows, issue };
}

function normalizedValue(value: string | number | undefined, column: Column): string | number {
  if (value === undefined) return '';
  if (column.type !== 'number' || typeof value === 'number' || !value.trim()) return value;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : value;
}

function changedCells(rows: readonly Row[], baseline: readonly Row[], columns: readonly Column[]): number {
  let changes = 0;
  for (let row = 0; row < rows.length; row++) {
    for (let column = 0; column < columns.length; column++) {
      if (rows[row].id !== baseline[row]?.id
        || !Object.is(normalizedValue(rows[row].values[column], columns[column]),
          normalizedValue(baseline[row]?.values[column], columns[column]))) changes++;
    }
  }
  return changes;
}

function SelectCell({ value, label, options, disabled, canInteract, onChange }: {
  value: string; label: string; options: Option[]; disabled: boolean;
  canInteract: () => boolean; onChange: (value: string) => void;
}) {
  const theme = useOpenUITheme();
  const [open, setOpen] = useState(false);
  const selected = options.find(option => option.value === value);
  return <>
    <Pressable accessibilityRole="button" accessibilityLabel={label}
      accessibilityValue={{ text: selected?.label ?? value }} accessibilityState={{ disabled, expanded: open }}
      disabled={disabled} onPress={() => { if (canInteract()) setOpen(true); }}
      style={{ minHeight: theme.controlMinHeight, justifyContent: 'center', padding: 8,
        borderWidth: 1, borderColor: theme.border, borderRadius: 8 }}>
      <Text style={{ color: theme.ink, fontSize: 14, lineHeight: 21 }}>{selected?.label || value || '选择…'} ▾</Text>
    </Pressable>
    <Modal visible={open} transparent animationType="fade" onRequestClose={() => setOpen(false)}>
      <View style={{ flex: 1, justifyContent: 'center', backgroundColor: '#00000066', padding: 24 }}>
        <View accessibilityViewIsModal style={{ maxHeight: '80%', borderRadius: 16, backgroundColor: theme.surface, padding: 16, gap: 12 }}>
          <Text accessibilityRole="header" style={{ color: theme.ink, fontSize: 18, lineHeight: 26 }}>{label}</Text>
          <ScrollView keyboardShouldPersistTaps="handled">
            {!options.length ? <Text style={{ color: theme.muted, padding: 12 }}>暂无可选项</Text> : null}
            {options.map((option, index) => <Pressable key={`${index}:${option.value}`} accessibilityRole="radio"
              accessibilityLabel={option.label} accessibilityState={{ checked: option.value === value, disabled }}
              disabled={disabled} onPress={() => { if (!canInteract()) return; onChange(option.value); setOpen(false); }}
              style={{ minHeight: theme.controlMinHeight, justifyContent: 'center', padding: 12,
                backgroundColor: option.value === value ? theme.surfaceMuted : theme.surface, borderRadius: 8 }}>
              <Text style={{ color: theme.ink, fontSize: 15, lineHeight: 22 }}>{option.value === value ? '● ' : '○ '}{option.label}</Text>
            </Pressable>)}
          </ScrollView>
          <TableAction label="取消选择" onPress={() => setOpen(false)} />
        </View>
      </View>
    </Modal>
  </>;
}

function EditableTableBody({ name, columns, columnIssue, initialData }: {
  name: string; columns: Column[]; columnIssue?: string; initialData: unknown;
}) {
  const theme = useOpenUITheme();
  const getFieldValue = useGetFieldValue();
  const setFieldValue = useSetFieldValue();
  const trigger = useTriggerAction();
  const streaming = useIsStreaming();
  const document = useDocumentInteraction();
  const policy = useNativeContentPolicy();
  const stored = getFieldValue(name, name);
  const source = useMemo(() => readRows(stored ?? initialData), [stored, initialData]);
  const sourceKey = JSON.stringify(source.rows);
  const identity = JSON.stringify([name, columns, source.rows.map(row => row.id)]);
  const guard = useFieldGuard(identity);
  const [draft, setDraft] = useState<Row[]>(() => source.rows);
  const [baseline, setBaseline] = useState<Row[]>(() => source.rows);
  const [conflict, setConflict] = useState<Row[]>();
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string>();
  const [invalidCells, setInvalidCells] = useState<ReadonlySet<string>>(new Set());
  const [page, setPage] = useState(0);
  const mounted = useRef(true);
  const incoming = useRef(sourceKey);
  const ownPublication = useRef<string | undefined>(undefined);
  const operation = useRef<object | undefined>(undefined);
  const draftRef = useRef(draft);
  const baselineRef = useRef(baseline);
  const issue = columnIssue ?? source.issue;
  const disabled = streaming || !document.canInteract() || saving || !!issue;
  const count = changedCells(draft, baseline, columns);
  const safePage = Math.min(page, Math.max(0, Math.ceil(draft.length / PAGE_SIZE) - 1));

  useLayoutEffect(() => { mounted.current = true; return () => { mounted.current = false; operation.current = undefined; }; }, []);
  useLayoutEffect(() => { draftRef.current = draft; baselineRef.current = baseline; }, [draft, baseline]);
  useEffect(() => {
    if (source.issue || incoming.current === sourceKey) return;
    incoming.current = sourceKey;
    if (ownPublication.current === sourceKey) return;
    ownPublication.current = undefined;
    // Keep an unsubmitted draft visible when a source refresh arrives. A user
    // must explicitly choose the source or the current draft before saving.
    if (changedCells(draftRef.current, baselineRef.current, columns) || operation.current) {
      // A later source must not be cleared when an earlier save Promise settles.
      operation.current = undefined; setSaving(false);
      setConflict(source.rows);
    } else {
      draftRef.current = source.rows; baselineRef.current = source.rows;
      setDraft(source.rows); setBaseline(source.rows); setConflict(undefined); setInvalidCells(new Set());
    }
  }, [sourceKey, source.issue, source.rows, columns]);

  // Picker sessions use callback identity to retire only a changed field. A
  // normal draft update must keep the current native picker session open.
  const editable = useCallback(() => guard() && !operation.current && !issue, [guard, issue]);
  const change = (rowIndex: number, columnIndex: number, value: string) => {
    if (!editable()) return;
    const next = draftRef.current.map((row, index) => {
      if (index !== rowIndex) return row;
      const values = [...row.values];
      while (values.length <= columnIndex) values.push('');
      values[columnIndex] = value;
      return { ...row, values };
    });
    draftRef.current = next; setDraft(next);
    setInvalidCells(current => { const next = new Set(current); next.delete(`${rowIndex}:${columnIndex}`); return next; });
    setError(undefined);
  };

  const save = async () => {
    if (!editable() || conflict || !changedCells(draftRef.current, baselineRef.current, columns)) return;
    const invalid = new Set<string>();
    const pending = draftRef.current.map((row, rowIndex) => {
      const values = [...row.values];
      for (let columnIndex = 0; columnIndex < columns.length; columnIndex++) {
        const column = columns[columnIndex];
        const raw = values[columnIndex];
        if (column.type === 'number' && typeof raw === 'string' && raw.trim() && !Number.isFinite(Number(raw))) {
          invalid.add(`${rowIndex}:${columnIndex}`);
        }
        values[columnIndex] = normalizedValue(raw, column);
      }
      return { id: row.id, values };
    });
    if (invalid.size) {
      setInvalidCells(invalid); setError('请先把标记的数字单元格改为有限数值。');
      const firstRow = Number([...invalid][0].split(':')[0]); setPage(Math.floor(firstRow / PAGE_SIZE));
      return;
    }
    const token = {};
    operation.current = token; setSaving(true); setError(undefined);
    ownPublication.current = JSON.stringify(pending);
    try {
      // The upstream contract uses a named form containing one named field.
      // Store commit is local; the following event asks the host what to do next.
      setFieldValue(name, 'EditableTable', name, pending);
      if (!guard() || operation.current !== token) return;
      await trigger('Save Changes', name);
      if (!guard() || operation.current !== token) return;
      draftRef.current = pending; baselineRef.current = pending;
      setDraft(pending); setBaseline(pending); setConflict(undefined); setInvalidCells(new Set());
    } catch (cause) {
      const reason = normalizeError(cause);
      if (guard() && operation.current === token) {
        setError('保存动作未完成，请重试。');
        try { policy.onError?.(reason); } catch { /* Diagnostics cannot turn a local save into an unhandled rejection. */ }
      }
    } finally {
      if (operation.current === token) {
        operation.current = undefined;
        if (mounted.current) setSaving(false);
      }
    }
  };

  const cell = (row: Row, rowIndex: number, column: Column, columnIndex: number) => {
    const value = cellText(row.values[columnIndex]);
    const label = `${column.header || column.key} · 第 ${rowIndex + 1} 行`;
    const invalid = invalidCells.has(`${rowIndex}:${columnIndex}`);
    const onChange = (next: string) => change(rowIndex, columnIndex, next);
    if (column.type === 'select') return <SelectCell value={value} label={label} options={column.options}
      disabled={disabled} canInteract={editable} onChange={onChange} />;
    if (column.type === 'date-single') return <NativeDateEditor value={value} label={label} disabled={disabled}
      canInteract={editable} onChange={isoDate => {
        const date = new Date(isoDate);
        if (!Number.isFinite(date.getTime())) return;
        // Table dates are date-only, in the same local calendar as the picker.
        onChange(`${String(date.getFullYear()).padStart(4, '0')}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`);
      }} />;
    return <TextInput accessibilityLabel={label} accessibilityState={{ disabled }}
      accessibilityHint={invalid ? '请输入有限数值' : undefined}
      value={value} editable={!disabled} onChangeText={onChange}
      keyboardType={column.type === 'number' ? Platform.OS === 'ios' ? 'numbers-and-punctuation' : 'numeric'
        : column.type === 'url' ? 'url' : 'default'}
      autoCapitalize={column.type === 'text' ? 'sentences' : 'none'} autoCorrect={column.type === 'text'}
      textContentType={column.type === 'url' ? 'URL' : 'none'}
      multiline={column.type === 'text'} placeholder={column.header}
      placeholderTextColor={theme.muted} selectionColor={theme.accent}
      underlineColorAndroid="transparent"
      style={{ minHeight: theme.controlMinHeight, borderWidth: 1, borderRadius: 8,
        borderColor: invalid ? theme.destructive : theme.border, paddingHorizontal: 10, paddingVertical: 8,
        fontSize: 14, lineHeight: 22, color: theme.ink, backgroundColor: disabled ? theme.surfaceMuted : theme.surface,
        textAlign: column.type === 'number' ? 'right' : 'left' }} />;
  };

  return <View testID="openui-editable-table" style={{ gap: 12, minWidth: 0 }}>
    {issue ? <Text accessibilityRole="alert" style={{ color: theme.destructive, fontSize: 14, lineHeight: 22 }}>{streaming ? '表格数据正在生成。' : issue}</Text> : null}
    <ScrollView horizontal nestedScrollEnabled keyboardShouldPersistTaps="handled">
      <View style={{ borderWidth: 1, borderColor: theme.border, borderRadius: 12, overflow: 'hidden' }}>
        <View style={{ flexDirection: 'row', backgroundColor: theme.surfaceMuted }}>
          {columns.map((column, index) => <View key={`${index}:${column.key}`} style={{ width: columnWidth(column.width), padding: 12 }}>
            <Text accessibilityRole="header" style={{ color: theme.ink, fontSize: 14, fontWeight: '600', lineHeight: 21,
              textAlign: column.type === 'number' ? 'right' : 'left' }}>{column.header}</Text>
          </View>)}
        </View>
        {draft.slice(safePage * PAGE_SIZE, (safePage + 1) * PAGE_SIZE).map((row, offset) => {
          const rowIndex = safePage * PAGE_SIZE + offset;
          return <View key={`${rowIndex}:${row.id}`} style={{ flexDirection: 'row', alignItems: 'center',
            backgroundColor: theme.surface, borderTopWidth: 0.5, borderColor: theme.border }}>
            {columns.map((column, columnIndex) => <View key={`${columnIndex}:${column.key}`}
              style={{ width: columnWidth(column.width), padding: 8 }}>
              {cell(row, rowIndex, column, columnIndex)}
            </View>)}
          </View>;
        })}
      </View>
    </ScrollView>
    {!draft.length ? <Text style={{ color: theme.muted, fontSize: 14 }}>{streaming ? '正在生成表格…' : '暂无数据'}</Text> : null}
    <Pagination page={safePage} count={draft.length} disabled={disabled}
      onPage={next => { if (editable()) setPage(next); }} />
    {conflict ? <View style={{ gap: 8, padding: 12, borderRadius: 10, backgroundColor: theme.surfaceMuted }}>
      <Text accessibilityRole="alert" style={{ color: theme.ink, fontSize: 14, lineHeight: 22 }}>源数据已经变化。请先选择使用新数据，或保留当前草稿。</Text>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
        <TableAction label="使用新数据" disabled={disabled} onPress={() => { if (!editable()) return;
          draftRef.current = conflict; baselineRef.current = conflict;
          setDraft(conflict); setBaseline(conflict); setConflict(undefined); setInvalidCells(new Set()); setError(undefined); }} />
        <TableAction label="保留当前草稿" disabled={disabled} onPress={() => { if (editable()) setConflict(undefined); }} />
      </View>
    </View> : null}
    {count > 0 ? <View style={{ gap: 8 }}>
      <Text accessibilityLiveRegion="polite" style={{ color: theme.muted, fontSize: 13 }}>{count} 个已修改单元格</Text>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
        <TableAction label="Reset" disabled={disabled} onPress={() => { if (!editable()) return;
          draftRef.current = baseline;
          setDraft(baseline); setInvalidCells(new Set()); setError(undefined); }} />
        <TableAction label="Save Changes" primary disabled={disabled || !!conflict} busy={saving} onPress={() => { void save(); }} />
      </View>
    </View> : null}
    {error ? <Text accessibilityRole="alert" style={{ color: theme.destructive, fontSize: 13, lineHeight: 20 }}>{error}</Text> : null}
  </View>;
}

const EditableTable: ComponentRenderer = ({ props }) => {
  const theme = useOpenUITheme();
  const streaming = useIsStreaming();
  const name = string(props.name);
  const definitions = useMemo(() => readColumns(props.columns), [props.columns]);
  // A different table name or positional column contract owns a different draft.
  const key = JSON.stringify([name, definitions.columns.map(column => [column.key, column.type])]);
  if (!definitions.columns.length) return <Text style={{ color: theme.muted, fontSize: 14 }}>{streaming ? '正在生成表格…' : definitions.issue ?? '暂无列定义'}</Text>;
  return <EditableTableBody key={key} name={name} columns={definitions.columns}
    columnIssue={definitions.issue} initialData={props.data ?? []} />;
};

export const tableRenderers: Record<string, ComponentRenderer> = { Table, Col: () => null, EditableTable };
