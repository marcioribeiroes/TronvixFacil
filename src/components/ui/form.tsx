"use client"

import { mergeProps } from "@base-ui/react/merge-props"
import { useRender } from "@base-ui/react/use-render"
import * as React from "react"
import {
  Controller,
  FormProvider,
  useFormContext,
  useFormState,
  type ControllerProps,
  type FieldPath,
  type FieldValues,
} from "react-hook-form"

import { Label } from "@/components/ui/label"
import { cn } from "@/lib/utils"

/**
 * Ponte entre o react-hook-form e os componentes de interface.
 *
 * Cuida do que e facil esquecer a mao e quebra a acessibilidade em silencio:
 * ligar o rotulo ao campo, apontar aria-describedby para a mensagem de erro e
 * marcar aria-invalid quando o campo esta invalido.
 *
 * Escrito sobre o Base UI (useRender), que e a base desta versao dos
 * componentes, em vez do Slot do Radix.
 */

const Form = FormProvider

type ContextoDoCampo<
  TFieldValues extends FieldValues = FieldValues,
  TName extends FieldPath<TFieldValues> = FieldPath<TFieldValues>,
> = { name: TName }

const ContextoDoCampoDoFormulario = React.createContext<ContextoDoCampo | null>(null)

function FormField<
  TFieldValues extends FieldValues = FieldValues,
  TName extends FieldPath<TFieldValues> = FieldPath<TFieldValues>,
>(props: ControllerProps<TFieldValues, TName>) {
  return (
    <ContextoDoCampoDoFormulario.Provider value={{ name: props.name }}>
      <Controller {...props} />
    </ContextoDoCampoDoFormulario.Provider>
  )
}

const ContextoDoItem = React.createContext<{ id: string } | null>(null)

function useFormField() {
  const campo = React.useContext(ContextoDoCampoDoFormulario)
  const item = React.useContext(ContextoDoItem)
  const { getFieldState } = useFormContext()
  const estadoDoFormulario = useFormState({ name: campo?.name })

  if (!campo || !item) {
    throw new Error("useFormField precisa estar dentro de <FormField> e <FormItem>.")
  }

  const estado = getFieldState(campo.name, estadoDoFormulario)

  return {
    id: item.id,
    name: campo.name,
    idDoCampo: `${item.id}-campo`,
    idDaDescricao: `${item.id}-descricao`,
    idDaMensagem: `${item.id}-mensagem`,
    ...estado,
  }
}

function FormItem({ className, ...props }: React.ComponentProps<"div">) {
  const id = React.useId()

  return (
    <ContextoDoItem.Provider value={{ id }}>
      <div data-slot="form-item" className={cn("grid gap-2", className)} {...props} />
    </ContextoDoItem.Provider>
  )
}

function FormLabel({ className, ...props }: React.ComponentProps<typeof Label>) {
  const { error, idDoCampo } = useFormField()

  return (
    <Label
      data-slot="form-label"
      data-error={!!error}
      className={cn("data-[error=true]:text-destructive", className)}
      htmlFor={idDoCampo}
      {...props}
    />
  )
}

/**
 * Envolve o campo real e injeta nele os atributos de acessibilidade. O campo e
 * passado pela prop `render`, do Base UI:
 *
 *   <FormControl render={<Input placeholder="..." />} />
 */
function FormControl({ render, ...props }: useRender.ComponentProps<"input">) {
  const { error, idDoCampo, idDaDescricao, idDaMensagem } = useFormField()

  return useRender({
    defaultTagName: "input",
    props: mergeProps<"input">(
      {
        id: idDoCampo,
        "aria-describedby": error ? `${idDaDescricao} ${idDaMensagem}` : idDaDescricao,
        "aria-invalid": !!error,
      },
      props,
    ),
    render,
    state: { slot: "form-control" },
  })
}

function FormDescription({ className, ...props }: React.ComponentProps<"p">) {
  const { idDaDescricao } = useFormField()

  return (
    <p
      data-slot="form-description"
      id={idDaDescricao}
      className={cn("text-muted-foreground text-sm", className)}
      {...props}
    />
  )
}

function FormMessage({ className, ...props }: React.ComponentProps<"p">) {
  const { error, idDaMensagem } = useFormField()
  const conteudo = error ? String(error.message ?? "") : props.children

  if (!conteudo) return null

  return (
    <p
      data-slot="form-message"
      id={idDaMensagem}
      // role="alert" para que o leitor de tela anuncie o erro quando ele
      // aparece, sem a pessoa precisar voltar ao campo para descobrir.
      role="alert"
      className={cn("text-destructive text-sm", className)}
      {...props}
    >
      {conteudo}
    </p>
  )
}

export {
  Form,
  FormControl,
  FormDescription,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
  useFormField,
}
