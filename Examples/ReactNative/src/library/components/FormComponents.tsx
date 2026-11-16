import { useId, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { Modal, Platform, Pressable, Switch, Text, View } from 'react-native';
import DateTimePicker, { type DateTimePickerEvent } from '@react-native-community/datetimepicker';
import NativeSlider from '@react-native-community/slider';
import { Picker } from '@react-native-picker/picker';
import {
  FormNameContext, FormValidationContext, useCreateFormValidation, useFormValidation,
  type ComponentRenderer,
} from '@openuidev/react-lang';
import { useOpenUITheme } from '../theme';
import { NativeTextField } from './Input';
import { FieldPresentationContext, useFieldGuard, useNativeField } from './useNativeField';

type Props = Record<string, unknown>;
type Child = { type: 'element'; typeName: string; props: Props; partial?: boolean };
const text = (value: unknown) => typeof value === 'string' ? value : '';
const object = (value: unknown): Props => value !== null && typeof value === 'object' && !Array.isArray(value)
  ? value as Props : {};
const finite = (value: unknown, fallback: number) => typeof value === 'number' && Number.isFinite(value) ? value : fallback;
function children(value: unknown, typeName: string): Child[] {
  return Array.isArray(value) ? value.filter((item): item is Child => {
    const node = object(item);
    return node.type === 'element' && node.typeName === typeName && node.props !== null && typeof node.props === 'object';
  }) : [];
}

function FieldError({ field }: { field: ReturnType<typeof useNativeField> }) {
  const theme = useOpenUITheme();
  return field.inlineError ? <Text accessibilityLiveRegion="polite"
    style={{ color: theme.destructive, fontSize: 13, lineHeight: 20 }}>{field.inlineError}</Text> : null;
}

function NativeForm({ props, renderNode }: Parameters<ComponentRenderer>[0]) {
  const validation = useCreateFormValidation();
  return <FormValidationContext.Provider value={validation}>
    <FormNameContext.Provider value={text(props.name)}>
      <View style={{ gap: 20 }}>{renderNode(props.fields)}{renderNode(props.buttons)}</View>
    </FormNameContext.Provider>
  </FormValidationContext.Provider>;
}

const Form: ComponentRenderer = props => <NativeForm key={text(props.props.name)} {...props} />;

const FormControl: ComponentRenderer = ({ props, renderNode }) => {
  const theme = useOpenUITheme();
  const validation = useFormValidation();
  const input = object(object(props.input).props);
  const error = validation?.errors[text(input.name)];
  const label = text(props.label);
  const hint = text(props.hint);
  const labelId = `openui-label-${useId()}`;
  const presentation = useMemo(() => ({ label, labelId, hint }), [label, labelId, hint]);
  return <FieldPresentationContext.Provider value={presentation}>
    <View style={{ gap: 8, minWidth: 0 }}>
      <View style={{ flexDirection: 'row', gap: 4, alignItems: 'baseline' }}>
        <Text nativeID={labelId} style={{ color: theme.ink, fontSize: 15, fontWeight: '600', lineHeight: 22 }}>{label}</Text>
        {object(input.rules).required === true ? <Text accessible={false} accessibilityElementsHidden
          importantForAccessibility="no-hide-descendants" style={{ color: theme.destructive }}>*</Text> : null}
      </View>
      {renderNode(props.input)}
      {error || hint ? <Text accessibilityLiveRegion={error ? 'polite' : 'none'}
        style={{ color: error ? theme.destructive : theme.muted, fontSize: 13, lineHeight: 20 }}>{error || hint}</Text> : null}
    </View>
  </FieldPresentationContext.Provider>;
};

const Label: ComponentRenderer = ({ props }) => {
  const theme = useOpenUITheme();
  return <Text style={{ color: theme.ink, fontSize: 15, lineHeight: 22, fontWeight: '600' }}>{text(props.text)}</Text>;
};

const TextArea: ComponentRenderer = ({ props }) => <NativeTextField props={props} multiline />;

const Select: ComponentRenderer = ({ props }) => {
  const theme = useOpenUITheme();
  const items = children(props.items, 'SelectItem').filter(item => text(item.props.value));
  const field = useNativeField(props, { identity: JSON.stringify(items.map(item => item.props.value)) });
  return <View style={{ gap: 6 }}>
    <View style={{ minHeight: theme.controlMinHeight, borderWidth: 1, borderRadius: 12,
      borderColor: field.error ? theme.destructive : theme.border,
      backgroundColor: field.disabled ? theme.surfaceMuted : theme.surface, overflow: 'hidden' }}>
      <Picker accessibilityLabel={field.label} accessibilityLabelledBy={field.labelledBy}
        accessibilityRole="combobox" accessibilityState={{ disabled: field.disabled }}
        accessibilityHint={field.error || field.hint} enabled={!field.disabled} mode="dropdown"
        selectedValue={text(field.value)} dropdownIconColor={theme.ink}
        itemStyle={{ color: theme.ink, fontSize: props.size === 'small' ? 14 : props.size === 'large' ? 18 : 16 }}
        style={{ color: theme.ink }}
        onValueChange={next => {
          if (typeof next === 'string' && items.some(item => item.props.value === next)) field.setValue(next);
        }}>
        <Picker.Item label={text(props.placeholder) || '请选择'} value="" enabled={false} color={theme.muted} />
        {items.map((item, index) => <Picker.Item key={`${text(item.props.value)}:${index}`}
          label={text(item.props.label) || text(item.props.value)} value={text(item.props.value)} color={theme.ink} />)}
      </Picker>
    </View>
    <FieldError field={field} />
  </View>;
};

function parseDate(value: unknown): Date | undefined {
  if (value instanceof Date) return Number.isFinite(value.getTime()) ? value : undefined;
  if (typeof value !== 'string' || !value) return undefined;
  const day = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  const date = day ? new Date(Number(day[1]), Number(day[2]) - 1, Number(day[3]), 12) : new Date(value);
  if (!Number.isFinite(date.getTime())) return undefined;
  if (day && (date.getFullYear() !== Number(day[1]) || date.getMonth() !== Number(day[2]) - 1
    || date.getDate() !== Number(day[3]))) return undefined;
  return date;
}
const dateLabel = (date: Date | undefined) => date ? `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}` : '选择日期';

/** Shared by the form field and editable-table cells; native dates persist as ISO JSON values. */
export function NativeDateEditor({ value, label, disabled = false, canInteract, onChange, minimumDate, maximumDate }: {
  value: unknown; label: string; disabled?: boolean; canInteract: () => boolean;
  onChange: (isoDate: string) => void; minimumDate?: Date; maximumDate?: Date;
}) {
  const theme = useOpenUITheme();
  const mounted = useRef(true);
  const enabled = useRef(!disabled);
  const [active, setActive] = useState<{
    token: object; date: Date; canInteract: () => boolean; onChange: (isoDate: string) => void;
    minimumDate?: Date; maximumDate?: Date;
  }>();
  const activeRef = useRef(active);
  useLayoutEffect(() => {
    mounted.current = true;
    return () => { mounted.current = false; };
  }, []);
  useLayoutEffect(() => { enabled.current = !disabled; }, [disabled]);
  const close = () => {
    if (mounted.current && activeRef.current?.token === active?.token) {
      activeRef.current = undefined;
      setActive(undefined);
    }
  };
  const change = (event: DateTimePickerEvent, next?: Date) => {
    if (!mounted.current || !enabled.current || !active || activeRef.current?.token !== active.token || !active.canInteract()) return;
    if (Platform.OS === 'android' || event.type === 'dismissed') close();
    if (event.type !== 'set' || !next || !Number.isFinite(next.getTime())) return;
    active.onChange(next.toISOString());
    if (Platform.OS !== 'android' && mounted.current && activeRef.current?.token === active.token && active.canInteract()) {
      const updated = { ...active, date: next };
      activeRef.current = updated;
      setActive(updated);
    }
  };
  const picker = active && !disabled && active.canInteract === canInteract && active.canInteract() ? <DateTimePicker value={active.date} mode="date"
    display={Platform.OS === 'ios' ? 'spinner' : 'default'} onChange={change}
    minimumDate={active.minimumDate} maximumDate={active.maximumDate} accessibilityLabel={label}
    textColor={theme.ink} accentColor={theme.accent} /> : null;
  return <>
    <Pressable accessibilityRole="button" accessibilityLabel={label}
      accessibilityValue={{ text: dateLabel(parseDate(value)) }} accessibilityState={{ disabled }}
      disabled={disabled} onPress={() => {
        if (!mounted.current || disabled || !canInteract()) return;
        let date = parseDate(value) ?? new Date();
        if (minimumDate && date < minimumDate) date = minimumDate;
        if (maximumDate && date > maximumDate) date = maximumDate;
        const opened = { token: {}, date, canInteract, onChange, minimumDate, maximumDate };
        activeRef.current = opened;
        setActive(opened);
      }} style={({ pressed }) => ({ minHeight: theme.controlMinHeight, borderWidth: 1,
        borderColor: theme.border, borderRadius: 12, padding: 12, justifyContent: 'center',
        backgroundColor: disabled ? theme.surfaceMuted : theme.surface, opacity: pressed ? 0.7 : 1 })}>
      <Text style={{ color: theme.ink, fontSize: 16 }}>{dateLabel(parseDate(value))}</Text>
    </Pressable>
    {Platform.OS === 'ios' ? <Modal transparent visible={Boolean(picker)} animationType="slide"
      onRequestClose={close}>
      <View style={{ flex: 1, justifyContent: 'flex-end', backgroundColor: '#00000066' }}>
        <View accessibilityViewIsModal style={{ backgroundColor: theme.surface, borderTopLeftRadius: 20,
          borderTopRightRadius: 20, padding: 20, paddingBottom: 36 }}>
          <Text accessibilityRole="header" style={{ color: theme.ink, fontSize: 18, fontWeight: '600' }}>{label}</Text>
          {picker}
          <Pressable accessibilityRole="button" accessibilityLabel={`完成${label}`} onPress={close}
            style={{ minHeight: theme.controlMinHeight, justifyContent: 'center', alignItems: 'center',
              borderRadius: 12, backgroundColor: theme.accent }}>
            <Text style={{ color: theme.onAccent, fontWeight: '600', fontSize: 16 }}>完成</Text>
          </Pressable>
        </View>
      </View>
    </Modal> : picker}
  </>;
}

const DatePicker: ComponentRenderer = ({ props }) => {
  const range = props.mode === 'range';
  const field = useNativeField(props, { identity: range ? 'range' : 'single',
    validationValue: range ? validDateRange : validDate });
  const selected = object(field.value);
  const from = parseDate(selected.from);
  const to = parseDate(selected.to);
  return <View style={{ gap: 8 }}>
    {range ? <>
      <NativeDateEditor label={`${field.label} · 开始日期`} value={selected.from} disabled={field.disabled}
        canInteract={field.canInteract} maximumDate={to} onChange={next => {
          field.setValue({ ...object(field.getValue()), from: next });
        }} />
      <NativeDateEditor label={`${field.label} · 结束日期`} value={selected.to} disabled={field.disabled}
        canInteract={field.canInteract} minimumDate={from} onChange={next => {
          field.setValue({ ...object(field.getValue()), to: next });
        }} />
    </> : <NativeDateEditor label={field.label} value={field.value} disabled={field.disabled}
      canInteract={field.canInteract} onChange={next => { field.setValue(next); }} />}
    <FieldError field={field} />
  </View>;
};
const validDate = (value: unknown) => parseDate(value) ? value : undefined;
const validDateRange = (value: unknown) => {
  const range = object(value);
  const from = parseDate(range.from); const to = parseDate(range.to);
  return from && to && from <= to ? value : undefined;
};

const firstNumber = (value: unknown) => Array.isArray(value) ? value[0] : value;
const Slider: ComponentRenderer = ({ props }) => {
  const theme = useOpenUITheme();
  const min = finite(props.min, 0); const max = finite(props.max, 100);
  const step = finite(props.step, props.variant === 'discrete' ? 1 : 0);
  const field = useNativeField(props, { fallback: props.defaultValue ?? [min], validationValue: firstNumber,
    identity: JSON.stringify([min, max, step, props.variant]) });
  const values = Array.isArray(field.value) && field.value.length ? field.value.map(value => finite(value, min)) : [min];
  const disabled = field.disabled || max <= min;
  const activeHandles = useFieldGuard(JSON.stringify([field.identity, values.length]), disabled);
  return <View style={{ gap: 8 }}>
    <Text style={{ color: theme.ink, fontSize: 15, fontWeight: '600' }}>{field.label}</Text>
    {values.map((value, index) => {
      const label = values.length > 1 ? `${field.label} ${index + 1}` : field.label;
      const shown = Math.max(min, Math.min(max, value));
      return <View key={index} style={{ gap: 2 }}>
        <Text style={{ color: theme.muted, fontSize: 13 }}>{label} · {Number(shown.toFixed(4))}</Text>
        <NativeSlider accessibilityLabel={label} accessibilityState={{ disabled }}
          accessibilityValue={{ min, max, now: shown }} disabled={disabled} value={shown}
          minimumValue={min} maximumValue={max > min ? max : min + 1}
          step={step > 0 && step <= max - min ? step : 0}
          minimumTrackTintColor={theme.accent} maximumTrackTintColor={theme.border} thumbTintColor={theme.accent}
          style={{ height: theme.controlMinHeight }}
          onValueChange={next => {
            if (disabled || !Number.isFinite(next) || !field.canInteract() || !activeHandles()) return;
            const stored = field.getValue();
            const current = Array.isArray(stored) && stored.length ? [...stored] : [...values];
            if (index >= current.length) return;
            const lower = Math.max(min, index > 0 ? finite(current[index - 1], min) : min);
            const upper = Math.min(max, index < current.length - 1 ? finite(current[index + 1], max) : max);
            current[index] = Math.max(lower, Math.min(upper, next));
            field.setValue(current);
          }} />
      </View>;
    })}
    <FieldError field={field} />
  </View>;
};

const checkedValues = (value: unknown) => Object.keys(object(value)).filter(key => object(value)[key] === true);
function BooleanChoices({ props, switches }: { props: Props; switches: boolean }) {
  const theme = useOpenUITheme();
  const items = children(props.items, switches ? 'SwitchItem' : 'CheckBoxItem');
  const defaults = Object.fromEntries(items.map(item => [text(item.props.name), item.props.defaultChecked === true]));
  const field = useNativeField(props, { fallback: defaults, validationValue: checkedValues,
    identity: JSON.stringify(items.map(item => [item.props.name, item.props.defaultChecked])) });
  const aggregate = (value = field.getValue()) => Object.fromEntries(items.map(item => {
    const key = text(item.props.name); const current = object(value)[key];
    return [key, typeof current === 'boolean' ? current : item.props.defaultChecked === true];
  }));
  const selected = aggregate(field.value);
  const card = switches && (props.variant === 'card' || props.variant === 'sunk');
  return <View style={{ gap: 8 }}>
    {items.map((item, index) => {
      const name = text(item.props.name); const label = text(item.props.label) || name;
      const description = text(item.props.description); const checked = selected[name] === true;
      const change = (next: boolean) => { if (field.canInteract()) field.setValue({ ...aggregate(), [name]: next }); };
      const content = <View style={{ flex: 1, gap: 3 }}>
        <Text style={{ color: theme.ink, fontSize: 16, lineHeight: 23 }}>{label}</Text>
        {description ? <Text style={{ color: theme.muted, fontSize: 13, lineHeight: 20 }}>{description}</Text> : null}
      </View>;
      const rowStyle = { minHeight: theme.controlMinHeight, flexDirection: 'row' as const, gap: 12,
        alignItems: 'center' as const, padding: card ? 14 : 8, borderRadius: 12,
        backgroundColor: card ? props.variant === 'sunk' ? theme.surfaceMuted : theme.surface : 'transparent',
        borderWidth: card ? 1 : 0, borderColor: theme.border, opacity: field.disabled ? 0.55 : 1 };
      return switches ? <View key={`${name}:${index}`} style={rowStyle}>
        {content}<Switch accessibilityLabel={label} accessibilityHint={description || field.error}
          accessibilityState={{ checked, disabled: field.disabled }} value={checked} disabled={field.disabled}
          trackColor={{ false: theme.border, true: theme.accent }} onValueChange={change} />
      </View> : <Pressable key={`${name}:${index}`} accessibilityRole="checkbox" accessibilityLabel={label}
        accessibilityHint={description || field.error} accessibilityState={{ checked, disabled: field.disabled }}
        disabled={field.disabled} onPress={() => change(!aggregate()[name])} style={rowStyle}>
        <View style={{ width: 24, height: 24, borderRadius: 6, borderWidth: 2, borderColor: checked ? theme.accent : theme.muted,
          backgroundColor: checked ? theme.accent : theme.surface, alignItems: 'center', justifyContent: 'center' }}>
          {checked ? <Text accessible={false} style={{ color: theme.onAccent, fontSize: 16, fontWeight: '700' }}>✓</Text> : null}
        </View>{content}
      </Pressable>;
    })}
    <FieldError field={field} />
  </View>;
}

const RadioGroup: ComponentRenderer = ({ props }) => {
  const theme = useOpenUITheme();
  const items = children(props.items, 'RadioItem');
  const field = useNativeField(props, { fallback: props.defaultValue,
    identity: JSON.stringify(items.map(item => item.props.value)) });
  return <View accessibilityRole="radiogroup" accessibilityLabel={field.label} style={{ gap: 8 }}>
    {items.map((item, index) => {
      const value = text(item.props.value); const checked = field.value === value;
      return <Pressable key={`${value}:${index}`} accessibilityRole="radio"
        accessibilityLabel={text(item.props.label) || value} accessibilityHint={text(item.props.description) || field.error}
        accessibilityState={{ checked, disabled: field.disabled }} disabled={field.disabled}
        onPress={() => { field.setValue(value); }}
        style={{ flexDirection: 'row', gap: 12, minHeight: theme.controlMinHeight, padding: 8,
          alignItems: 'center', opacity: field.disabled ? 0.55 : 1 }}>
        <View style={{ width: 24, height: 24, borderRadius: 12, borderWidth: 2,
          borderColor: checked ? theme.accent : theme.muted, justifyContent: 'center', alignItems: 'center' }}>
          {checked ? <View style={{ width: 12, height: 12, borderRadius: 6, backgroundColor: theme.accent }} /> : null}
        </View><View style={{ flex: 1, gap: 3 }}>
          <Text style={{ color: theme.ink, fontSize: 16, lineHeight: 23 }}>{text(item.props.label) || value}</Text>
          {text(item.props.description) ? <Text style={{ color: theme.muted, fontSize: 13, lineHeight: 20 }}>{text(item.props.description)}</Text> : null}
        </View>
      </Pressable>;
    })}
    <FieldError field={field} />
  </View>;
};

function selection(value: unknown, multiple: boolean): string[] {
  const values = Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string' && Boolean(item))
    : typeof value === 'string' && value ? [value] : [];
  return multiple ? values : values.slice(0, 1);
}
const selectedValue = (value: unknown) => Array.isArray(value) ? value.length ? value : undefined : value || undefined;

function SelectionChoices({ props, renderNode, cards }: Parameters<ComponentRenderer>[0] & { cards: boolean }) {
  const theme = useOpenUITheme();
  const multiple = props.type === 'multiple' || (props.type !== 'single' && !cards);
  const items = children(props.items, cards ? 'OptionCard' : 'ChipItem').filter(item => text(item.props.value));
  const defaultKey = JSON.stringify(props.defaultValue ?? null);
  const fallback = useMemo(() => {
    if (props.defaultValue === undefined || props.defaultValue === null) return undefined;
    const values = selection(JSON.parse(defaultKey), multiple);
    return multiple ? values : values[0] ?? '';
  }, [defaultKey, multiple]);
  const field = useNativeField(props, { fallback, hydrateDefault: cards ? 'OptionCards' : 'Chips', validationValue: selectedValue,
    identity: JSON.stringify([multiple, items.map(item => [item.props.value, item.props.disabled])]) });
  const values = selection(field.value, multiple);
  return <View style={{ gap: 8 }}>
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 10 }}>
      {items.map((item, index) => {
        const value = text(item.props.value); const checked = values.includes(value);
        const disabled = field.disabled || item.props.disabled === true;
        const title = text(cards ? item.props.title : item.props.label) || value;
        return <Pressable key={`${value}:${index}`} accessibilityRole={multiple ? 'checkbox' : 'radio'}
          accessibilityLabel={title} accessibilityHint={text(item.props.subtitle) || field.error}
          accessibilityState={{ checked, disabled }} disabled={disabled} onPress={() => {
            if (disabled || !field.canInteract()) return;
            const current = selection(field.getValue(), multiple);
            const next = multiple ? current.includes(value) ? current.filter(item => item !== value) : [...current, value]
              : current[0] === value ? [] : [value];
            // Empty string is the JSON-safe cleared state, distinct from an absent default.
            field.setValue(multiple ? next : next[0] ?? '');
          }} style={({ pressed }) => ({ minHeight: theme.controlMinHeight, minWidth: cards ? 140 : undefined,
            flexBasis: cards ? '45%' : undefined, flexGrow: cards ? 1 : 0, flexShrink: 1,
            gap: 8, paddingHorizontal: 14, paddingVertical: cards ? 16 : 10, borderRadius: cards ? 14 : 24,
            borderWidth: checked ? 2 : 1, borderColor: checked ? theme.accent : theme.border,
            backgroundColor: checked ? theme.surfaceMuted : theme.surface, opacity: disabled ? 0.5 : pressed ? 0.7 : 1,
            justifyContent: 'center' })}>
          {renderNode(cards ? item.props.topContent : item.props.icon)}
          <Text style={{ color: checked ? theme.accent : theme.ink, fontSize: 15, lineHeight: 22, fontWeight: '600' }}>{title}</Text>
          {cards && text(item.props.subtitle) ? <Text style={{ color: theme.muted, fontSize: 13, lineHeight: 20 }}>{text(item.props.subtitle)}</Text> : null}
        </Pressable>;
      })}
    </View>
    <FieldError field={field} />
  </View>;
}

const dataItem: ComponentRenderer = () => null;
export const formRenderers: Record<string, ComponentRenderer> = {
  Form, FormControl, Label, TextArea, Select, SelectItem: dataItem, DatePicker, Slider,
  CheckBoxGroup: ({ props }) => <BooleanChoices props={props} switches={false} />, CheckBoxItem: dataItem,
  RadioGroup, RadioItem: dataItem,
  SwitchGroup: ({ props }) => <BooleanChoices props={props} switches />, SwitchItem: dataItem,
  Chips: props => <SelectionChoices {...props} cards={false} />, ChipItem: dataItem,
  OptionCards: props => <SelectionChoices {...props} cards />, OptionCard: dataItem,
};
