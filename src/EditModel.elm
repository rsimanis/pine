module EditModel exposing
  ( Input, Controller, Attributes, ModelUpdater, InputValidator, Formatter, SelectInitializer
  , EditModel, Msg, Tomsg
  , init, setModelUpdater, setFormatter, setSelectInitializer, setInputValidator
  , fetch, set, create, http, save, delete
  , id, data, inp, inps, simpleCtrl, simpleSelectCtrl, noCmdUpdater, controller, inputMsg
  , update
  )

{-| Binding layer between [`Input`](#Input) representing form input field and [`JsonModel`](JsonModel).
[Controller](#Controller) functions are responsible for binding.

# Commands
@docs fetch, set, create, http, save, delete

# Inuput attributes (input is associated with controller)
@docs inputEvents, onSelectInput, onSelectMouse

# Utility
@docs id, noCmd, input

# Types
@docs Controller, EditModel, Input, InputWithAttributes, Msg, Tomsg

@docs update
-}


import JsonModel as JM
import Ask
import Select exposing (..)
import Utils

import Html exposing (Attribute)
import Html.Attributes as Attrs
import Html.Events exposing (..)
import Task
import Http
import Dict exposing (..)

import Debug exposing (toString, log)


{-| Represents form input field. Is synchronized with model. -}
type alias Input msg =
  { value: String
  , editing: Bool
  , error: Maybe String
  , select: Maybe (SelectModel msg String)
  , label: String
  , type_: String
  , required: Bool
  , length: Maybe Int
  , decimalPlaces: Maybe Int
  , attrs: Attributes msg
  }


{-| Updates model from `Input` optionally emiting command. -}
type alias ModelUpdater msg model = Tomsg msg model -> Input msg -> model -> (model, Cmd msg)


{-| Validates input -}
type alias InputValidator = String -> Result String String


{- Get input field text from model. Function is called when value is selected from list or model
   data are refreshed from update or fetch messages. Bool argument depends on EditModel.isEditable field
   so data can be formatted according to display mode.
-}
type alias Formatter model = model -> String


type alias SelectInitializer msg =
  Select.Tomsg msg String -> -- toSelectmsg
  Ask.Tomsg msg -> -- toMessagemsg
  String -> -- search string
  (String -> msg) -> -- select msg
  (SelectModel msg String, Cmd msg)


{-| Controller. Binds [`Input`](#Input) together with [JsonModel](JsonModel) -}
type Controller msg model =
  Controller
    { name: String
    , updateModel: ModelUpdater msg model -- called on OnSelect, OnFocus _ False
    , formatter: Formatter model
    , selectInitializer: Maybe (SelectInitializer msg) -- called on OnFocus _ True
    , validateInput: InputValidator -- called on OnMsg, OnSelect
    }


{-| Input together with proposed html input element attributes and with
mouse selection attributes of select component.
-}
type alias Attributes msg =
  { mouseSelectAttrs: Int -> List (Attribute msg)
  , attrs: List (Attribute msg)
  }


{-| Edit model -}
type alias EditModel msg model =
  { model: JM.FormModel msg model
  , controllers: Dict String (Controller msg model)
  , inputs: Dict String (Input msg)
  , toMessagemsg: Ask.Tomsg msg
  --, validate: Tomsg msg model -> model -> (Result String model, Cmd msg)
  --, error: Maybe String
  , isSaving: Bool
  , isDeleting: Bool
  --, isValidating: Bool
  , isEditable: Bool
  }


{-| Edit model update messages -}
type Msg msg model
  = UpdateModelMsg Bool (JM.FormMsg msg model)
  | FetchModelMsg (JM.FormMsg msg model)
  | SaveModelMsg (JM.FormMsg msg model)
  | CreateModelMsg (model -> model) (JM.FormMsg msg model)
  | DeleteModelMsg (JM.FormMsg msg model)
  -- select components messages
  | SelectMsg (Controller msg model) (Select.Msg msg String)
  -- input fields event messages
  | OnMsg (Controller msg model) String
  | OnFocusMsg (Controller msg model) Bool
  | OnSelectMsg (Controller msg model) String
  -- update entire model
  | EditModelMsg (model -> model)
  | NewModelMsg JM.SearchParams (model -> model)
  | HttpModelMsg (Maybe model) (Result Http.Error model)


{-| Edit model message constructor -}
type alias Tomsg msg model = (Msg msg model -> msg)


{-| Initializes model
-}
init: JM.FormModel msg model -> List (key, Controller msg model) -> Ask.Tomsg msg  -> EditModel msg model
init model ctrlList toMessagemsg =
  let
    controllers =
      ctrlList |>
      List.map (\(k, Controller c) -> (toString k, Controller { c | name = toString k })) |>
      Dict.fromList

    emptyAttrs =
      Attributes (always []) []

    inputs =
      controllers |>
      Dict.map (\k _ -> Input "" False Nothing Nothing "" "text" False Nothing Nothing emptyAttrs)
  in
    EditModel
      model
      controllers
      inputs
      toMessagemsg
      False
      False
      True


setModelUpdater: key -> ModelUpdater msg model -> EditModel msg model -> EditModel msg model
setModelUpdater key updater model =
  updateController key (\(Controller c) -> Controller { c | updateModel = updater }) model


setFormatter: key -> Formatter model -> EditModel msg model -> EditModel msg model
setFormatter key formatter model =
  updateController key (\(Controller c) -> Controller { c | formatter = formatter }) model


setSelectInitializer: key -> Maybe (SelectInitializer msg) -> EditModel msg model -> EditModel msg model
setSelectInitializer key initializer model =
  updateController
    key
    (\(Controller c) -> Controller { c | selectInitializer = initializer }) model


setInputValidator: key -> InputValidator -> EditModel msg model -> EditModel msg model
setInputValidator key validator model =
  updateController key (\(Controller c) -> Controller { c | validateInput = validator }) model


updateController: key -> (Controller msg model -> Controller msg model) -> EditModel msg model -> EditModel msg model
updateController key updater model =
  Dict.get (toString key) model.controllers |>
  Maybe.map updater |>
  Maybe.map (\c -> Dict.insert (toString key) c model.controllers) |>
  Maybe.map (\cs -> { model | controllers = cs}) |>
  Maybe.withDefault model


{-| Fetch data by id from server. Calls [`JsonModel.fetch`](JsonModel#fetch)
-}
fetch: Tomsg msg model -> Int -> Cmd msg
fetch toMsg fid =
  JM.fetch (toMsg << FetchModelMsg) <| [ ("id", String.fromInt fid) ]


{-| Set model data. After updating inputs, calls [`JsonModel.set`](JsonModel#set)
-}
set: Tomsg msg model -> (model -> model) -> Cmd msg
set toMsg editFun =
  Task.perform toMsg <| Task.succeed <| EditModelMsg editFun


{-| Creates model data, calling [`JsonModel.set`](JsonModel#create).
After that call function `createFun` on received data.
-}
create: Tomsg msg model -> JM.SearchParams -> (model -> model) -> Cmd msg
create toMsg createParams createFun =
  Task.perform toMsg <| Task.succeed <| NewModelMsg createParams createFun


{-| Creates model from http request.
-}
http: Tomsg msg model -> Maybe model -> Http.Request model -> Cmd msg
http toMsg maybeOnErr req =
  Http.send (toMsg << HttpModelMsg maybeOnErr) req


{-| Save model to server.  Calls [`JsonModel.save`](JsonModel#save)
-}
save: Tomsg msg model -> Cmd msg
save toMsg =
  JM.save (toMsg << SaveModelMsg) []


{-| Save model from server.  Calls [`JsonModel.delete`](JsonModel#delete)
-}
delete: Tomsg msg model -> Int -> Cmd msg
delete toMsg did =
  JM.delete (toMsg << DeleteModelMsg) [("id", String.fromInt did)]


{-| Gets model id.  Calls [`JsonModel.id`](JsonModel#id) and tries to convert result to `Int`
-}
id: EditModel msg model -> Maybe Int
id =
  .model >> JM.id >> Maybe.andThen String.toInt


{-| Gets model data.
-}
data: EditModel msg model -> model
data { model } =
  JM.data model


{-| Creates simple controller -}
simpleCtrl: (String -> model -> model) -> Formatter model -> Controller msg model
simpleCtrl updateModel formatter =
  Controller
    { name = ""
    , updateModel = noCmdUpdater updateModel
    , formatter = formatter
    , selectInitializer = Nothing
    , validateInput = Ok
    }


{-| Creates simple controller with select list -}
simpleSelectCtrl: (String -> model -> model) -> Formatter model -> SelectInitializer msg -> Controller msg model
simpleSelectCtrl updateModel formatter selectInitializer =
  Controller
    { name = ""
    , updateModel = noCmdUpdater updateModel
    , formatter = formatter
    , selectInitializer = Just selectInitializer
    , validateInput = Ok
    }


noCmdUpdater: (String -> model -> model) -> ModelUpdater msg model
noCmdUpdater updater =
  \_ input mod -> (updater input.value mod, Cmd.none)


{-| Creates controller -}
controller:
  ModelUpdater msg model ->
  Formatter model ->
  Maybe (SelectInitializer msg) ->
  InputValidator ->
  Controller msg model
controller updateModel formatter selectInitializer validator =
  Controller
    { name = ""
    , updateModel = updateModel
    , formatter = formatter
    , selectInitializer = selectInitializer
    , validateInput = validator
    }


{-| Gets input from model for rendering. Function furnishes input with attributes
    using `InputAttrs`
-}
inp: key -> Tomsg msg model -> List (Attribute msg) -> EditModel msg model -> Maybe (Input msg)
inp key toMsg staticAttrs { controllers, inputs } =
  let
    ks = toString key
  in
    Dict.get ks controllers |>
    Maybe.map2
      (\input ctl ->
        let
          inputEventAttrs =
            [ onInput <| toMsg << OnMsg ctl
            , onFocus <| toMsg <| OnFocusMsg ctl True
            , onBlur <| toMsg <| OnFocusMsg ctl False
            ]

          selectEventAttrs =
            input.select |>
            Maybe.map
              ( always
                  ( Select.onSelectInput <| toMsg << SelectMsg ctl
                  , Select.onMouseSelect <| toMsg << SelectMsg ctl
                  )
              ) |>
            Maybe.withDefault ([], always [])

          attrs =
            (Attrs.value input.value :: staticAttrs) ++
            inputEventAttrs ++
            Tuple.first selectEventAttrs
        in
          { input | attrs = Attributes (Tuple.second selectEventAttrs) attrs }
      )
      (Dict.get ks inputs)


{-| Gets inputs from model for rendering
-}
inps: List (key, List (Attribute msg)) -> Tomsg msg model -> EditModel msg model -> List (Input msg)
inps keys toMsg model =
  List.foldl
    (\(k, ia) r -> inp k toMsg ia model |> Maybe.map (\i -> i :: r) |> Maybe.withDefault r)
    []
    keys |>
  List.reverse


{-| Produces `OnSelectMsg` input message. This can be used on input events like `onCheck` or `onClick`
-}
inputMsg: key -> Tomsg msg model -> EditModel msg model -> Maybe (String -> msg)
inputMsg key toMsg { controllers } =
  Dict.get (toString key) controllers |>
  Maybe.map (\ctrl -> toMsg << OnSelectMsg ctrl)


{-| Model update -}
update: Tomsg msg model -> Msg msg model -> EditModel msg model -> (EditModel msg model, Cmd msg)
update toMsg msg ({ model, inputs, controllers } as same) =
  let
    updateModelFromInput newInputs ctrl input =
      let
        mod = JM.data model
      in
        if ctrl.formatter mod == input.value then
          ( { same | inputs = newInputs }, Cmd.none )
        else
          ctrl.updateModel toMsg input mod |>
          (\(nm, cmd) ->
            ( { same | inputs = updateInputsFromModel nm newInputs } --update inputs if updater has changed other fields
            , if cmd == Cmd.none then JM.set (toMsg << UpdateModelMsg False) nm else cmd
            )
          )

    updateInput ctrl value newInputs =
      Dict.get ctrl.name newInputs |>
      Maybe.map
        (\input ->
          case ctrl.validateInput value of
            Ok val ->
              { input |
                value = value
              , error = Nothing
              , select = input.select |> Maybe.map (Select.updateSearch value)
              }

            Err err ->
              { input | value = value, error = Just err }
        ) |>
      Maybe.map (\input -> (Dict.insert ctrl.name input newInputs, Just input)) |>
      Maybe.withDefault (newInputs, Nothing)

    applyInput toSelectmsg ctrl value = -- OnMsg
      updateInput ctrl value inputs |>
      Tuple.mapBoth
        (\newInputs -> { same | inputs = newInputs })
        ( Maybe.andThen .select >>
          Maybe.map (always <| Select.search toSelectmsg value) >>
          Maybe.withDefault Cmd.none
        )

    setEditing ctrl focus =  -- OnFocus
      let
        processFocusSelect input =
          if focus then
            ctrl.selectInitializer |>
            Maybe.map
              (\initializer ->
                initializer
                  (toMsg << SelectMsg (Controller ctrl))
                  same.toMessagemsg
                  input.value
                  (toMsg << OnSelectMsg (Controller ctrl))
              ) |>
            Maybe.map
              (Tuple.mapFirst (\sel -> { input | editing = True, select = Just sel })) |>
            Maybe.withDefault ({ input | editing = True, select = Nothing }, Cmd.none)
          else ({ input | editing = False, select = Nothing }, Cmd.none)

        focusOrUpdateModel newInputs input selCmd =
          if focus then
            ( { same | inputs = newInputs }, selCmd )
          else
            updateModelFromInput newInputs ctrl input
      in
        Dict.get ctrl.name inputs |>
        Maybe.map processFocusSelect |>
        Maybe.map
          (\(input, selCmd) ->
            focusOrUpdateModel (Dict.insert ctrl.name input inputs) input selCmd
          ) |>
        Maybe.withDefault ( same, Cmd.none )

    applySelect ctrl toSelmsg selMsg = -- SelectMsg
      let
        input = Dict.get ctrl.name inputs
      in
        input |>
        Maybe.andThen .select |>
        Maybe.map2
          (\selinp sel ->
            Select.update toSelmsg selMsg sel |>
            Tuple.mapFirst (\sm -> { selinp | select = Just sm })
          )
          input |>
        Maybe.map
          (Tuple.mapFirst
            (\selinp -> { same | inputs = Dict.insert ctrl.name selinp inputs })
          ) |>
        Maybe.withDefault ( same, Cmd.none )

    updateInputsFromModel newModel newInputs =
      Dict.foldl
        (\key input foldedinps ->
          Dict.get key controllers |>
          Maybe.map
            (\(Controller ctrl) ->
              updateInput ctrl (ctrl.formatter newModel) foldedinps |> Tuple.first
            ) |>
          Maybe.withDefault foldedinps
        )
        newInputs
        newInputs

    updateModel doInputUpdate newModel =
      { same |
        model = newModel
      , inputs =
          if doInputUpdate then
            updateInputsFromModel (JM.data newModel) same.inputs
          else same.inputs
      }

    applyCreateModel newModel =
      { same | model = newModel }

    createCmd createFun cmd =
      if cmd == Cmd.none then set toMsg createFun else cmd

    applyModel (newModel, cmd) =
      updateModel (cmd == Cmd.none) newModel

    applyFetchModel newModelAndCmd =
      applyModel newModelAndCmd

    applySaveModel newModelAndCmd =
      applyModel newModelAndCmd |>
      (\m -> { m | isSaving = Tuple.second newModelAndCmd /= Cmd.none })

    applyDeleteModel newModelAndCmd =
      applyModel newModelAndCmd |>
      (\m -> { m | isDeleting = Tuple.second newModelAndCmd /= Cmd.none })
  in
    case msg of
      -- JM model messages
      UpdateModelMsg doInputUpdate value ->
        JM.update (toMsg << UpdateModelMsg doInputUpdate) value model |>
        (\(jm, cmd) -> (updateModel (cmd == Cmd.none && doInputUpdate) jm, cmd)) -- update inputs at the end

      FetchModelMsg value ->
        JM.update (toMsg << FetchModelMsg) value model |>
        (\mc -> (applyFetchModel mc, Tuple.second mc))

      SaveModelMsg value ->
        JM.update (toMsg << SaveModelMsg) value model |>
        (\mc -> (applySaveModel mc, Tuple.second mc))

      CreateModelMsg createFun value ->
        JM.update (toMsg << CreateModelMsg createFun) value model |>
        Tuple.mapBoth applyCreateModel (createCmd createFun)

      DeleteModelMsg value ->
        JM.update (toMsg << DeleteModelMsg) value model |>
        (\mc -> (applyDeleteModel mc, Tuple.second mc))

      -- Select messages
      SelectMsg (Controller ctrl) selMsg -> -- field select list messages
        applySelect ctrl (toMsg << SelectMsg (Controller ctrl)) selMsg

      -- user input messages
      OnMsg (Controller ctrl) value ->
        applyInput (toMsg << SelectMsg (Controller ctrl)) ctrl value

      OnFocusMsg (Controller ctrl) focus ->
        setEditing ctrl focus

      OnSelectMsg (Controller ctrl) value -> -- text selected from select component
        updateInput ctrl value inputs |>
        (\(newInputs, maybeInp) ->
          maybeInp |>
          Maybe.map (updateModelFromInput newInputs ctrl) |>
          Maybe.withDefault ( same, Cmd.none )
        )

      --edit entire model
      EditModelMsg editFun ->
        ( same, JM.set (toMsg << UpdateModelMsg True) <| editFun <| JM.data model )

      NewModelMsg searchParams createFun ->
        ( same, JM.create (toMsg << CreateModelMsg createFun) searchParams )

      HttpModelMsg onErr httpResult ->
        let
            result =
              case httpResult of
                Ok r ->
                  set toMsg (always r)

                Err e ->
                  onErr |>
                  Maybe.map (\r -> set toMsg (always r)) |>
                  Maybe.withDefault (Ask.errorOrUnauthorized same.toMessagemsg e)
        in
          ( same, result )
