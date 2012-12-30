{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}

module Db (
    User(..)
  , Todo(..)
  , createTables
  , saveTodo
  , listTodos) where

import           Control.Applicative
import           Control.Monad
import           Data.Aeson
import           Data.Maybe
import qualified Data.Text as T
import qualified Database.SQLite.Simple as S
import           Snap.Snaplet
import           Snap.Snaplet.SqliteSimple
------------------------------------------------------------------------------
import           Application

data User = User Int T.Text

data Todo =
  Todo
  { todoId :: Maybe Int
  , todoText :: T.Text
  , todoDone :: Bool
  } deriving (Show)

instance FromJSON Todo where
  parseJSON (Object v) =
    Todo <$> optional (v .: "id")
         <*> v .: "text"
         <*> v .: "done"
  parseJSON _ = mzero

instance ToJSON Todo where
  toJSON (Todo i text done) =
    object [ "id" .= fromJust i
           , "text" .= text
           , "done" .= done
           ]

instance FromRow Todo where
  fromRow = Todo <$> field <*> field <*> field

tableExists :: S.Connection -> String -> IO Bool
tableExists conn tblName = do
  r <- S.query conn "SELECT name FROM sqlite_master WHERE type='table' AND name=?" (Only tblName)
  case r of
    [Only (_ :: String)] -> return True
    _ -> return False

-- | Create the necessary database tables, if not already initialized.
createTables :: S.Connection -> IO ()
createTables conn = do
  -- Note: for a bigger app, you probably want to create a 'version'
  -- table too and use it to keep track of schema version and
  -- implement your schema upgrade procedure here.
  schemaCreated <- tableExists conn "todos"
  unless schemaCreated $
    S.execute_ conn
      (S.Query $
       T.concat [ "CREATE TABLE todos ("
                , "id INTEGER PRIMARY KEY, "
                , "user_id INTEGER NOT NULL, "
                , "saved_on TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL, "
                , "text TEXT, "
                , "done BOOLEAN)"])

-- | Retrieve a user's list of comments
listTodos :: User -> Handler App Sqlite [Todo]
listTodos (User uid _) =
  query "SELECT id,text,done FROM todos WHERE user_id = ?" (Only uid)

-- | Save or update a todo
saveTodo :: User -> Todo -> Handler App Sqlite ()
saveTodo (User uid _) t =
  maybe newTodo updateTodo (todoId t)
  where
    newTodo =
      execute "INSERT INTO todos (user_id,text,done) VALUES (?,?,?)"
        (uid, todoText t, todoDone t)

    updateTodo tid =
      execute "UPDATE todos SET text = ?, done = ? WHERE (user_id = ? AND id = ?)"
        (todoText t, todoDone t, uid, tid)